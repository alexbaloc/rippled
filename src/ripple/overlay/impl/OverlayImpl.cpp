//------------------------------------------------------------------------------
/*
    This file is part of rippled: https://github.com/ripple/rippled
    Copyright (c) 2012, 2013 Ripple Labs Inc.

    Permission to use, copy, modify, and/or distribute this software for any
    purpose  with  or without fee is hereby granted, provided that the above
    copyright notice and this permission notice appear in all copies.

    THE  SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
    WITH  REGARD  TO  THIS  SOFTWARE  INCLUDING  ALL  IMPLIED  WARRANTIES  OF
    MERCHANTABILITY  AND  FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
    ANY  SPECIAL ,  DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
    WHATSOEVER  RESULTING  FROM  LOSS  OF USE, DATA OR PROFITS, WHETHER IN AN
    ACTION  OF  CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
    OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
//==============================================================================

#include <BeastConfig.h>
#include <ripple/app/misc/HashRouter.h>
#include <ripple/app/misc/NetworkOPs.h>
#include <ripple/core/DatabaseCon.h>
#include <ripple/basics/contract.h>
#include <ripple/basics/Log.h>
#include <ripple/basics/make_SSLContext.h>
#include <ripple/protocol/JsonFields.h>
#include <ripple/server/JsonWriter.h>
#include <ripple/overlay/Cluster.h>
#include <ripple/overlay/impl/ConnectAttempt.h>
#include <ripple/overlay/impl/OverlayImpl.h>
#include <ripple/overlay/impl/PeerImp.h>
#include <ripple/overlay/impl/TMHello.h>
#include <ripple/peerfinder/make_Manager.h>
#include <ripple/protocol/STExchange.h>
#include <ripple/beast/core/ByteOrder.h>
#include <beast/detail/base64.hpp>
#include <ripple/beast/core/LexicalCast.h>
#include <beast/http/rfc2616.hpp>
#include <beast/detail/ci_char_traits.hpp>
#include <ripple/beast/utility/WrappedSink.h>

#include <boost/utility/in_place_factory.hpp>

namespace ripple {

/** A functor to visit all active peers and retrieve their JSON data */
struct get_peer_json
{
    using return_type = Json::Value;

    Json::Value json;

    get_peer_json ()
    { }

    void operator() (Peer::ptr const& peer)
    {
        json.append (peer->json ());
    }

    Json::Value operator() ()
    {
        return json;
    }
};

//------------------------------------------------------------------------------

OverlayImpl::Child::Child (OverlayImpl& overlay)
    : overlay_(overlay)
{
}

OverlayImpl::Child::~Child()
{
    overlay_.remove(*this);
}

//------------------------------------------------------------------------------

OverlayImpl::Timer::Timer (OverlayImpl& overlay)
    : Child(overlay)
    , timer_(overlay_.io_service_)
{
}

void
OverlayImpl::Timer::stop()
{
    error_code ec;
    timer_.cancel(ec);
}

void
OverlayImpl::Timer::run()
{
    error_code ec;
    timer_.expires_from_now (std::chrono::seconds(1));
    timer_.async_wait(overlay_.strand_.wrap(
        std::bind(&Timer::on_timer, shared_from_this(),
            beast::asio::placeholders::error)));
}

void
OverlayImpl::Timer::on_timer (error_code ec)
{
    if (ec || overlay_.isStopping())
    {
        if (ec && ec != boost::asio::error::operation_aborted)
        {
            JLOG(overlay_.journal_.error()) << "on_timer: " << ec.message();
        }
        return;
    }

    overlay_.m_peerFinder->once_per_second();
    overlay_.sendEndpoints();
    overlay_.autoConnect();

    if ((++overlay_.timer_count_ % Tuning::checkSeconds) == 0)
        overlay_.check();

    timer_.expires_from_now (std::chrono::seconds(1));
    timer_.async_wait(overlay_.strand_.wrap(std::bind(
        &Timer::on_timer, shared_from_this(),
            beast::asio::placeholders::error)));
}

//------------------------------------------------------------------------------

OverlayImpl::OverlayImpl (
    Application& app,
    Setup const& setup,
    Stoppable& parent,
    ServerHandler& serverHandler,
    Resource::Manager& resourceManager,
    Resolver& resolver,
    boost::asio::io_service& io_service,
    BasicConfig const& config)
    : Overlay (parent)
    , app_ (app)
    , io_service_ (io_service)
    , work_ (boost::in_place(std::ref(io_service_)))
    , strand_ (io_service_)
    , setup_(setup)
    , journal_ (app_.journal("Overlay"))
    , serverHandler_(serverHandler)
    , m_resourceManager (resourceManager)
    , m_peerFinder (PeerFinder::make_Manager (*this, io_service,
        stopwatch(), app_.journal("PeerFinder"), config))
    , m_resolver (resolver)
    , next_id_(1)
    , timer_count_(0)
{
    beast::PropertyStream::Source::add (m_peerFinder.get());
}

OverlayImpl::~OverlayImpl ()
{
    stop();

    // Block until dependent objects have been destroyed.
    // This is just to catch improper use of the Stoppable API.
    //
    std::unique_lock <decltype(mutex_)> lock (mutex_);
    cond_.wait (lock, [this] { return list_.empty(); });
}

//------------------------------------------------------------------------------

Handoff
OverlayImpl::onHandoff (std::unique_ptr <beast::asio::ssl_bundle>&& ssl_bundle,
    http_request_type&& request,
        endpoint_type remote_endpoint)
{
    auto const id = next_id_++;
    beast::WrappedSink sink (app_.logs()["Peer"], makePrefix(id));
    beast::Journal journal (sink);

    Handoff handoff;
    if (processRequest(request, handoff))
        return handoff;
    if (! isPeerUpgrade(request))
        return handoff;

    handoff.moved = true;

    JLOG(journal.debug()) << "Peer connection upgrade from " << remote_endpoint;

    error_code ec;
    auto const local_endpoint (ssl_bundle->socket.local_endpoint(ec));
    if (ec)
    {
        JLOG(journal.debug()) << remote_endpoint << " failed: " << ec.message();
        return handoff;
    }

    auto consumer = m_resourceManager.newInboundEndpoint(
        beast::IPAddressConversion::from_asio(remote_endpoint));
    if (consumer.disconnect())
        return handoff;

    auto const slot = m_peerFinder->new_inbound_slot (
        beast::IPAddressConversion::from_asio(local_endpoint),
            beast::IPAddressConversion::from_asio(remote_endpoint));

    if (slot == nullptr)
    {
        // self-connect, close
        handoff.moved = false;
        return handoff;
    }

    // TODO Validate HTTP request

    {
        auto const types = beast::rfc2616::split_commas(
            request.headers["Connect-As"]);
        if (std::find_if(types.begin(), types.end(),
                [](std::string const& s)
                {
                    return beast::detail::ci_equal(s, "peer");
                }) == types.end())
        {
            handoff.moved = false;
            handoff.response = makeRedirectResponse(slot, request,
                remote_endpoint.address());
            handoff.keep_alive = is_keep_alive(request);
            return handoff;
        }
    }

    handoff.moved = true;

    auto hello = parseHello (true, request.headers, journal);
    if(! hello)
        return handoff;

    auto sharedValue = makeSharedValue(
        ssl_bundle->stream.native_handle(), journal);
    if(! sharedValue)
        return handoff;

    auto publicKey = verifyHello (*hello,
        *sharedValue,
        setup_.public_ip,
        beast::IPAddressConversion::from_asio(
            remote_endpoint), journal, app_);
    if(! publicKey)
        return handoff;

    auto const result = m_peerFinder->activate (slot, *publicKey,
        static_cast<bool>(app_.cluster().member(*publicKey)));
    if (result != PeerFinder::Result::success)
    {
        m_peerFinder->on_closed(slot);
        JLOG(journal.debug()) <<
            "Peer " << remote_endpoint << " redirected, slots full";
        handoff.moved = false;
        handoff.response = makeRedirectResponse(slot, request,
            remote_endpoint.address());
        handoff.keep_alive = is_keep_alive(request);
        return handoff;
    }

    auto const peer = std::make_shared<PeerImp>(app_, id,
        remote_endpoint, slot, std::move(request), *hello,
            *publicKey, consumer, std::move(ssl_bundle), *this);
    {
        // As we are not on the strand, run() must be called
        // while holding the lock, otherwise new I/O can be
        // queued after a call to stop().
        std::lock_guard <decltype(mutex_)> lock (mutex_);
        {
            auto const result =
                m_peers.emplace (peer->slot(), peer);
            assert (result.second);
            (void) result.second;
        }
        list_.emplace(peer.get(), peer);

        peer->run();
    }
    handoff.moved = true;
    return handoff;
}

//------------------------------------------------------------------------------

bool
OverlayImpl::isPeerUpgrade(http_request_type const& request)
{
    if (! is_upgrade(request))
        return false;
    auto const versions = parse_ProtocolVersions(
        request.headers["Upgrade"]);
    if (versions.size() == 0)
        return false;
    return true;
}

bool
OverlayImpl::isPeerUpgrade(beast::deprecated_http::message const& request)
{
    if (! request.upgrade())
        return false;
    auto const versions = parse_ProtocolVersions(
        request.headers["Upgrade"]);
    if (versions.size() == 0)
        return false;
    if(! request.request() && request.status() != 101)
        return false;
    return true;
}

std::string
OverlayImpl::makePrefix (std::uint32_t id)
{
    std::stringstream ss;
    ss << "[" << std::setfill('0') << std::setw(3) << id << "] ";
    return ss.str();
}

std::shared_ptr<Writer>
OverlayImpl::makeRedirectResponse (PeerFinder::Slot::ptr const& slot,
    http_request_type const& request, address_type remote_address)
{
    Json::Value json(Json::objectValue);
    {
        auto const result = m_peerFinder->redirect(slot);
        Json::Value& ips = (json["peer-ips"] = Json::arrayValue);
        for (auto const& _ : m_peerFinder->redirect(slot))
            ips.append(_.address.to_string());
    }

    beast::deprecated_http::message m;
    m.request(false);
    m.status(503);
    m.reason("Service Unavailable");
    m.headers.insert("Remote-Address", remote_address.to_string());
    m.version(std::make_pair(request.version / 10, request.version % 10));
    if (request.version == 10)
    {
        //?
    }
    auto const response = make_JsonWriter (m, json);
    return response;
}

//------------------------------------------------------------------------------

void
OverlayImpl::connect (beast::IP::Endpoint const& remote_endpoint)
{
    assert(work_);

    auto usage = resourceManager().newOutboundEndpoint (remote_endpoint);
    if (usage.disconnect())
    {
        JLOG(journal_.info()) << "Over resource limit: " << remote_endpoint;
        return;
    }

    auto const slot = peerFinder().new_outbound_slot(remote_endpoint);
    if (slot == nullptr)
    {
        JLOG(journal_.debug()) << "Connect: No slot for " << remote_endpoint;
        return;
    }

    auto const p = std::make_shared<ConnectAttempt>(app_,
        io_service_, beast::IPAddressConversion::to_asio_endpoint(remote_endpoint),
            usage, setup_.context, next_id_++, slot,
                app_.journal("Peer"), *this);

    std::lock_guard<decltype(mutex_)> lock(mutex_);
    list_.emplace(p.get(), p);
    p->run();
}

//------------------------------------------------------------------------------

// Adds a peer that is already handshaked and active
void
OverlayImpl::add_active (std::shared_ptr<PeerImp> const& peer)
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);

    {
        auto const result =
            m_peers.emplace (peer->slot(), peer);
        assert (result.second);
        (void) result.second;
    }

    {
        auto const result = ids_.emplace (
            std::piecewise_construct,
                std::make_tuple (peer->id()),
                    std::make_tuple (peer));
        assert(result.second);
        (void) result.second;
    }

    list_.emplace(peer.get(), peer);

    JLOG(journal_.debug()) <<
        "activated " << peer->getRemoteAddress() <<
        " (" << peer->id() << ":" <<
        toBase58 (
            TokenType::TOKEN_NODE_PUBLIC,
            peer->getNodePublic()) << ")";

    // As we are not on the strand, run() must be called
    // while holding the lock, otherwise new I/O can be
    // queued after a call to stop().
    peer->run();
}

void
OverlayImpl::remove (PeerFinder::Slot::ptr const& slot)
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    auto const iter = m_peers.find (slot);
    assert(iter != m_peers.end ());
    m_peers.erase (iter);
}

//------------------------------------------------------------------------------
//
// Stoppable
//
//------------------------------------------------------------------------------

// Caller must hold the mutex
void
OverlayImpl::checkStopped ()
{
    if (isStopping() && areChildrenStopped () && list_.empty())
        stopped();
}

void
OverlayImpl::setupValidatorKeyManifests (BasicConfig const& config,
                                         DatabaseCon& db)
{
    auto const loaded = manifestCache_.loadValidatorKeys (
        config.section ("validator_keys"),
        journal_);

    if (!loaded)
        Throw<std::runtime_error> (
            "Unable to load keys from [validator_keys]");

    auto const validation_manifest =
        config.section ("validation_manifest");

    if (! validation_manifest.lines().empty())
    {
        std::string s;
        for (auto const& line : validation_manifest.lines())
            s += beast::rfc2616::trim(line);
        s = beast::detail::base64_decode(s);
        if (auto mo = make_Manifest (std::move (s)))
        {
            manifestCache_.configManifest (
                std::move (*mo),
                app_.validators(),
                journal_);
        }
        else
        {
            Throw<std::runtime_error> ("Malformed manifest in config");
        }
    }
    else
    {
        JLOG(journal_.debug()) << "No [validation_manifest] section in config";
    }

    manifestCache_.load (
        db,
        app_.validators(),
        journal_);
}

void
OverlayImpl::saveValidatorKeyManifests (DatabaseCon& db) const
{
    manifestCache_.save (db);
}

void
OverlayImpl::onPrepare()
{
    PeerFinder::Config config;

    if (app_.config().PEERS_MAX != 0)
        config.maxPeers = app_.config().PEERS_MAX;

    config.outPeers = config.calcOutPeers();

    auto const port = serverHandler_.setup().overlay.port;

    config.peerPrivate = app_.config().PEER_PRIVATE;
    config.wantIncoming =
        (! config.peerPrivate) && (port != 0);
    // if it's a private peer or we are running as standalone
    // automatic connections would defeat the purpose.
    config.autoConnect =
        !app_.config().RUN_STANDALONE &&
        !app_.config().PEER_PRIVATE;
    config.listeningPort = port;
    config.features = "";
    config.ipLimit = setup_.ipLimit;

    // Enforce business rules
    config.applyTuning();

    m_peerFinder->setConfig (config);

    // Populate our boot cache: if there are no entries in [ips] then we use
    // the entries in [ips_fixed]. If both are empty, we resort to a round-robin
    // pool.
    auto bootstrapIps = app_.config().IPS.empty()
        ? app_.config().IPS_FIXED
        : app_.config().IPS;
    if (bootstrapIps.empty ())
        bootstrapIps.push_back ("r.ripple.com 51235");

    m_resolver.resolve (bootstrapIps,
        [this](std::string const& name,
            std::vector <beast::IP::Endpoint> const& addresses)
        {
            std::vector <std::string> ips;
            ips.reserve(addresses.size());
            for (auto const& addr : addresses)
            {
                if (addr.port () == 0)
                {
                    Throw<std::runtime_error> ("Port not specified for "
                        "address:" + addr.to_string ());
                }

                ips.push_back (to_string (addr));
            }

            std::string const base ("config: ");
            if (!ips.empty ())
                m_peerFinder->addFallbackStrings (base + name, ips);
        });

    // Add the ips_fixed from the rippled.cfg file
    if (! app_.config().RUN_STANDALONE && !app_.config().IPS_FIXED.empty ())
    {
        m_resolver.resolve (app_.config().IPS_FIXED,
            [this](
                std::string const& name,
                std::vector <beast::IP::Endpoint> const& addresses)
            {
                if (!addresses.empty ())
                    m_peerFinder->addFixedPeer (name, addresses);
            });
    }
}

void
OverlayImpl::onStart ()
{
    auto const timer = std::make_shared<Timer>(*this);
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    list_.emplace(timer.get(), timer);
    timer_ = timer;
    timer->run();
}

void
OverlayImpl::onStop ()
{
    strand_.dispatch(std::bind(&OverlayImpl::stop, this));
}

void
OverlayImpl::onChildrenStopped ()
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    checkStopped ();
}

//------------------------------------------------------------------------------
//
// PropertyStream
//
//------------------------------------------------------------------------------

void
OverlayImpl::onWrite (beast::PropertyStream::Map& stream)
{
    beast::PropertyStream::Set set ("traffic", stream);
    auto stats = m_traffic.getCounts();
    for (auto& i : stats)
    {
        if (! i.second.messagesIn && ! i.second.messagesOut)
            continue;

        beast::PropertyStream::Map item (set);
        item["category"] = i.first;
        item["bytes_in"] =
            beast::lexicalCast<std::string>
                (i.second.bytesIn.load());
        item["messages_in"] =
            beast::lexicalCast<std::string>
                (i.second.messagesIn.load());
        item["bytes_out"] =
            beast::lexicalCast<std::string>
                (i.second.bytesOut.load());
        item["messages_out"] =
            beast::lexicalCast<std::string>
                (i.second.messagesOut.load());
    }
}

//------------------------------------------------------------------------------
/** A peer has connected successfully
    This is called after the peer handshake has been completed and during
    peer activation. At this point, the peer address and the public key
    are known.
*/
void
OverlayImpl::activate (std::shared_ptr<PeerImp> const& peer)
{
    // Now track this peer
    {
        std::lock_guard <decltype(mutex_)> lock (mutex_);
        auto const result (ids_.emplace (
            std::piecewise_construct,
                std::make_tuple (peer->id()),
                    std::make_tuple (peer)));
        assert(result.second);
        (void) result.second;
    }

    JLOG(journal_.debug()) <<
        "activated " << peer->getRemoteAddress() <<
        " (" << peer->id() <<
        ":" << toBase58 (
            TokenType::TOKEN_NODE_PUBLIC,
            peer->getNodePublic()) << ")";

    // We just accepted this peer so we have non-zero active peers
    assert(size() != 0);
}

void
OverlayImpl::onPeerDeactivate (Peer::id_t id)
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    ids_.erase(id);
}

void
OverlayImpl::onManifests (
    std::shared_ptr<protocol::TMManifests> const& m,
        std::shared_ptr<PeerImp> const& from)
{
    auto& hashRouter = app_.getHashRouter();
    auto const n = m->list_size();
    auto const& journal = from->pjournal();

    JLOG(journal.debug()) << "TMManifest, " << n << (n == 1 ? " item" : " items");

    bool const history = m->history ();
    for (std::size_t i = 0; i < n; ++i)
    {
        auto& s = m->list ().Get (i).stobject ();

        if (auto mo = make_Manifest (s))
        {
            uint256 const hash = mo->hash ();
            if (!hashRouter.addSuppressionPeer (hash, from->id ()))
                continue;

            auto const serialized = mo->serialized;
            auto const result = manifestCache_.applyManifest (
                std::move(*mo),
                app_.validators(),
                journal);

            if (result == ManifestDisposition::accepted ||
                    result == ManifestDisposition::untrusted)
                app_.getOPs().pubManifest (*make_Manifest(serialized));

            if (result == ManifestDisposition::accepted)
            {
                auto db = app_.getWalletDB ().checkoutDb ();

                soci::transaction tr(*db);
                static const char* const sql =
                        "INSERT INTO ValidatorManifests (RawData) VALUES (:rawData);";
                soci::blob rawData(*db);
                convert (serialized, rawData);
                *db << sql, soci::use (rawData);
                tr.commit ();
            }

            if (history)
            {
                // Historical manifests are sent on initial peer connections.
                // They do not need to be forwarded to other peers.
                std::set<Peer::id_t> peers;
                hashRouter.swapSet (hash, peers, SF_RELAYED);
                continue;
            }

            if (result == ManifestDisposition::accepted)
            {
                protocol::TMManifests o;
                o.add_list ()->set_stobject (s);

                std::set<Peer::id_t> peers;
                hashRouter.swapSet (hash, peers, SF_RELAYED);
                foreach (send_if_not (
                    std::make_shared<Message>(o, protocol::mtMANIFESTS),
                    peer_in_set (peers)));
            }
            else
            {
                JLOG(journal.info()) << "Bad manifest #" << i + 1;
            }
        }
        else
        {
            JLOG(journal.warn()) << "Malformed manifest #" << i + 1;
            continue;
        }
    }
}

void
OverlayImpl::reportTraffic (
    TrafficCount::category cat,
    bool isInbound,
    int number)
{
    m_traffic.addCount (cat, isInbound, number);
}

std::size_t
OverlayImpl::selectPeers (PeerSet& set, std::size_t limit,
    std::function<bool(std::shared_ptr<Peer> const&)> score)
{
    using item = std::pair<int, std::shared_ptr<PeerImp>>;

    std::vector<item> v;
    v.reserve(size());

    for_each ([&](std::shared_ptr<PeerImp>&& e)
    {
        auto const s = e->getScore(score(e));
        v.emplace_back(s, std::move(e));
    });

    std::sort(v.begin(), v.end(),
        [](item const& lhs, item const&rhs)
        {
            return lhs.first > rhs.first;
        });

    std::size_t accepted = 0;
    for (auto const& e : v)
    {
        if (set.insert(e.second) && ++accepted >= limit)
            break;
    }
    return accepted;
}

/** The number of active peers on the network
    Active peers are only those peers that have completed the handshake
    and are running the Ripple protocol.
*/
std::size_t
OverlayImpl::size()
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    return ids_.size ();
}

int
OverlayImpl::limit()
{
    return m_peerFinder->config().maxPeers;
}

Json::Value
OverlayImpl::crawl()
{
    using namespace std::chrono;
    Json::Value jv;
    auto& av = jv["active"] = Json::Value(Json::arrayValue);

    for_each ([&](std::shared_ptr<PeerImp>&& sp)
    {
        auto& pv = av.append(Json::Value(Json::objectValue));
        pv[jss::public_key] = beast::detail::base64_encode(
            sp->getNodePublic().data(),
                sp->getNodePublic().size());
        pv[jss::type] = sp->slot()->inbound() ?
            "in" : "out";
        pv[jss::uptime] =
            static_cast<std::uint32_t>(duration_cast<seconds>(
                sp->uptime()).count());
        if (sp->crawl())
        {
            pv[jss::ip] = sp->getRemoteAddress().address().to_string();
            if (sp->slot()->inbound())
            {
                if (auto port = sp->slot()->listening_port())
                    pv[jss::port] = *port;
            }
            else
            {
                pv[jss::port] = std::to_string(
                    sp->getRemoteAddress().port());
            }
        }
        auto version = sp->getVersion ();
        if (!version.empty ())
            pv["version"] = version;
    });

    return jv;
}

// Returns information on verified peers.
Json::Value
OverlayImpl::json ()
{
    return foreach (get_peer_json());
}

bool
OverlayImpl::processRequest (http_request_type const& req,
    Handoff& handoff)
{
    if (req.url != "/crawl")
        return false;

    beast::deprecated_http::message resp;
    resp.request(false);
    resp.status(200);
    resp.reason("OK");
    resp.version(std::make_pair(req.version / 10, req.version % 10));
    Json::Value v;
    v["overlay"] = crawl();
    handoff.response = make_JsonWriter(resp, v);
    return true;
}

Overlay::PeerSequence
OverlayImpl::getActivePeers()
{
    Overlay::PeerSequence ret;
    ret.reserve(size());

    for_each ([&ret](std::shared_ptr<PeerImp>&& sp)
    {
        ret.emplace_back(std::move(sp));
    });

    return ret;
}

void
OverlayImpl::checkSanity (std::uint32_t index)
{
    for_each ([index](std::shared_ptr<PeerImp>&& sp)
    {
        sp->checkSanity (index);
    });
}

void
OverlayImpl::check ()
{
    for_each ([](std::shared_ptr<PeerImp>&& sp)
    {
        sp->check ();
    });
}

Peer::ptr
OverlayImpl::findPeerByShortID (Peer::id_t const& id)
{
    std::lock_guard <decltype(mutex_)> lock (mutex_);
    auto const iter = ids_.find (id);
    if (iter != ids_.end ())
        return iter->second.lock();
    return Peer::ptr();
}

void
OverlayImpl::send (protocol::TMProposeSet& m)
{
    if (setup_.expire)
        m.set_hops(0);
    auto const sm = std::make_shared<Message>(
        m, protocol::mtPROPOSE_LEDGER);
    for_each([&](std::shared_ptr<PeerImp>&& p)
    {
        if (! m.has_hops() || p->hopsAware())
            p->send(sm);
    });
}
void
OverlayImpl::send (protocol::TMValidation& m)
{
    if (setup_.expire)
        m.set_hops(0);
    auto const sm = std::make_shared<Message>(
        m, protocol::mtVALIDATION);
    for_each([&](std::shared_ptr<PeerImp>&& p)
    {
        if (! m.has_hops() || p->hopsAware())
            p->send(sm);
    });
}

void
OverlayImpl::relay (protocol::TMProposeSet& m,
    uint256 const& uid)
{
    if (m.has_hops() && m.hops() >= maxTTL)
        return;
    std::set<Peer::id_t> skip;
    if (! app_.getHashRouter().swapSet (
            uid, skip, SF_RELAYED))
        return;
    auto const sm = std::make_shared<Message>(
        m, protocol::mtPROPOSE_LEDGER);
    for_each([&](std::shared_ptr<PeerImp>&& p)
    {
        if (skip.find(p->id()) != skip.end())
            return;
        if (! m.has_hops() || p->hopsAware())
            p->send(sm);
    });
}

void
OverlayImpl::relay (protocol::TMValidation& m,
    uint256 const& uid)
{
    if (m.has_hops() && m.hops() >= maxTTL)
        return;
    std::set<Peer::id_t> skip;
    if (! app_.getHashRouter().swapSet (
            uid, skip, SF_RELAYED))
        return;
    auto const sm = std::make_shared<Message>(
        m, protocol::mtVALIDATION);
    for_each([&](std::shared_ptr<PeerImp>&& p)
    {
        if (skip.find(p->id()) != skip.end())
            return;
        if (! m.has_hops() || p->hopsAware())
            p->send(sm);
    });
}

//------------------------------------------------------------------------------

void
OverlayImpl::remove (Child& child)
{
    std::lock_guard<decltype(mutex_)> lock(mutex_);
    list_.erase(&child);
    if (list_.empty())
        checkStopped();
}

void
OverlayImpl::stop()
{
    std::lock_guard<decltype(mutex_)> lock(mutex_);
    if (work_)
    {
        work_ = boost::none;
        for (auto& _ : list_)
        {
            auto const child = _.second.lock();
            // Happens when the child is about to be destroyed
            if (child != nullptr)
                child->stop();
        }
    }
}

void
OverlayImpl::autoConnect()
{
    auto const result = m_peerFinder->autoconnect();
    for (auto addr : result)
        connect (addr);
}

void
OverlayImpl::sendEndpoints()
{
    auto const result = m_peerFinder->buildEndpointsForPeers();
    for (auto const& e : result)
    {
        std::shared_ptr<PeerImp> peer;
        {
            std::lock_guard <decltype(mutex_)> lock (mutex_);
            auto const iter = m_peers.find (e.first);
            if (iter != m_peers.end())
                peer = iter->second.lock();
        }
        if (peer)
            peer->sendEndpoints (e.second.begin(), e.second.end());
    }
}

//------------------------------------------------------------------------------

bool ScoreHasLedger::operator()(std::shared_ptr<Peer> const& bp) const
{
    auto const& p = std::dynamic_pointer_cast<PeerImp>(bp);
    return p->hasLedger (hash_, seq_);
}

bool ScoreHasTxSet::operator()(std::shared_ptr<Peer> const& bp) const
{
    auto const& p = std::dynamic_pointer_cast<PeerImp>(bp);
    return p->hasTxSet (hash_);
}

//------------------------------------------------------------------------------

Overlay::Setup
setup_Overlay (BasicConfig const& config)
{
    Overlay::Setup setup;
    auto const& section = config.section("overlay");
    setup.context = make_SSLContext();
    setup.expire = get<bool>(section, "expire", false);

    set (setup.ipLimit, "ip_limit", section);
    if (setup.ipLimit < 0)
        Throw<std::runtime_error> ("Configured IP limit is invalid");

    std::string ip;
    set (ip, "public_ip", section);
    if (! ip.empty ())
    {
        bool valid;
        std::tie (setup.public_ip, valid) =
            beast::IP::Address::from_string (ip);
        if (! valid || ! setup.public_ip.is_v4() ||
                is_private (setup.public_ip))
            Throw<std::runtime_error> ("Configured public IP is invalid");
    }
    return setup;
}

std::unique_ptr <Overlay>
make_Overlay (
    Application& app,
    Overlay::Setup const& setup,
    Stoppable& parent,
    ServerHandler& serverHandler,
    Resource::Manager& resourceManager,
    Resolver& resolver,
    boost::asio::io_service& io_service,
    BasicConfig const& config)
{
    return std::make_unique<OverlayImpl>(app, setup, parent, serverHandler,
        resourceManager, resolver, io_service, config);
}

}
