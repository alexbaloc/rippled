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
#include <ripple/overlay/Cluster.h>
#include <ripple/overlay/impl/ConnectAttempt.h>
#include <ripple/overlay/impl/PeerImp.h>
#include <ripple/overlay/impl/Tuning.h>
#include <ripple/json/json_reader.h>

namespace ripple {

ConnectAttempt::ConnectAttempt (Application& app, boost::asio::io_service& io_service,
    endpoint_type const& remote_endpoint, Resource::Consumer usage,
        beast::asio::ssl_bundle::shared_context const& context,
            std::uint32_t id, PeerFinder::Slot::ptr const& slot,
                beast::Journal journal, OverlayImpl& overlay)
    : Child (overlay)
    , app_ (app)
    , id_ (id)
    , sink_ (journal, OverlayImpl::makePrefix(id))
    , journal_ (sink_)
    , remote_endpoint_ (remote_endpoint)
    , usage_ (usage)
    , strand_ (io_service)
    , timer_ (io_service)
    , ssl_bundle_ (std::make_unique<beast::asio::ssl_bundle>(
        context, io_service))
    , socket_ (ssl_bundle_->socket)
    , stream_ (ssl_bundle_->stream)
    , parser_ (
        [&](void const* data, std::size_t size)
        {
            body_.commit(boost::asio::buffer_copy(body_.prepare(size),
                boost::asio::buffer(data, size)));
        }
        , response_, false)
    , slot_ (slot)
{
    JLOG(journal_.debug()) <<
        "Connect " << remote_endpoint;
}

ConnectAttempt::~ConnectAttempt()
{
    if (slot_ != nullptr)
        overlay_.peerFinder().on_closed(slot_);
    JLOG(journal_.trace()) <<
        "~ConnectAttempt";
}

void
ConnectAttempt::stop()
{
    if (! strand_.running_in_this_thread())
        return strand_.post(std::bind(
            &ConnectAttempt::stop, shared_from_this()));
    if (stream_.next_layer().is_open())
    {
        JLOG(journal_.debug()) <<
            "Stop";
    }
    close();
}

void
ConnectAttempt::run()
{
    error_code ec;
    stream_.next_layer().async_connect (remote_endpoint_,
        strand_.wrap (std::bind (&ConnectAttempt::onConnect,
            shared_from_this(), beast::asio::placeholders::error)));
}

//------------------------------------------------------------------------------

void
ConnectAttempt::close()
{
    assert(strand_.running_in_this_thread());
    if (stream_.next_layer().is_open())
    {
        error_code ec;
        timer_.cancel(ec);
        socket_.close(ec);
        JLOG(journal_.debug()) <<
            "Closed";
    }
}

void
ConnectAttempt::fail (std::string const& reason)
{
    assert(strand_.running_in_this_thread());
    if (stream_.next_layer().is_open())
    {
        JLOG(journal_.debug()) <<
            reason;
    }
    close();
}

void
ConnectAttempt::fail (std::string const& name, error_code ec)
{
    assert(strand_.running_in_this_thread());
    if (stream_.next_layer().is_open())
    {
        JLOG(journal_.debug()) <<
            name << ": " << ec.message();
    }
    close();
}

void
ConnectAttempt::setTimer()
{
    error_code ec;
    timer_.expires_from_now(std::chrono::seconds(15), ec);
    if (ec)
    {
        JLOG(journal_.error()) <<
            "setTimer: " << ec.message();
        return;
    }

    timer_.async_wait(strand_.wrap(std::bind(
        &ConnectAttempt::onTimer, shared_from_this(),
            beast::asio::placeholders::error)));
}

void
ConnectAttempt::cancelTimer()
{
    error_code ec;
    timer_.cancel(ec);
}

void
ConnectAttempt::onTimer (error_code ec)
{
    if (! stream_.next_layer().is_open())
        return;
    if (ec == boost::asio::error::operation_aborted)
        return;
    if (ec)
    {
        // This should never happen
        JLOG(journal_.error()) <<
            "onTimer: " << ec.message();
        return close();
    }
    fail("Timeout");
}

void
ConnectAttempt::onConnect (error_code ec)
{
    cancelTimer();

    if(ec == boost::asio::error::operation_aborted)
        return;
    endpoint_type local_endpoint;
    if(! ec)
        local_endpoint = stream_.next_layer().local_endpoint(ec);
    if(ec)
        return fail("onConnect", ec);
    if(! stream_.next_layer().is_open())
        return;
    JLOG(journal_.trace()) <<
        "onConnect";

    setTimer();
    stream_.set_verify_mode (boost::asio::ssl::verify_none);
    stream_.async_handshake (boost::asio::ssl::stream_base::client,
        strand_.wrap (std::bind (&ConnectAttempt::onHandshake,
            shared_from_this(), beast::asio::placeholders::error)));
}

void
ConnectAttempt::onHandshake (error_code ec)
{
    cancelTimer();
    if(! stream_.next_layer().is_open())
        return;
    if(ec == boost::asio::error::operation_aborted)
        return;
    endpoint_type local_endpoint;
    if (! ec)
        local_endpoint = stream_.next_layer().local_endpoint(ec);
    if(ec)
        return fail("onHandshake", ec);
    JLOG(journal_.trace()) <<
        "onHandshake";

    if (! overlay_.peerFinder().onConnected (slot_,
            beast::IPAddressConversion::from_asio (local_endpoint)))
        return fail("Duplicate connection");

    auto sharedValue = makeSharedValue(
        stream_.native_handle(), journal_);
    if (! sharedValue)
        return close(); // makeSharedValue logs

    beast::deprecated_http::message req = makeRequest(
        ! overlay_.peerFinder().config().peerPrivate,
            remote_endpoint_.address());
    auto const hello = buildHello (
        *sharedValue,
        overlay_.setup().public_ip,
        beast::IPAddressConversion::from_asio(remote_endpoint_),
        app_);
    appendHello (req.headers, hello);

    beast::deprecated_http::write (write_buf_, req);

    setTimer();
    stream_.async_write_some (write_buf_.data(),
        strand_.wrap (std::bind (&ConnectAttempt::onWrite,
            shared_from_this(), beast::asio::placeholders::error,
                beast::asio::placeholders::bytes_transferred)));
}

void
ConnectAttempt::onWrite (error_code ec, std::size_t bytes_transferred)
{
    cancelTimer();

    if(! stream_.next_layer().is_open())
        return;
    if(ec == boost::asio::error::operation_aborted)
        return;
    if(ec)
        return fail("onWrite", ec);
    JLOG(journal_.trace()) <<
        "onWrite: " << bytes_transferred << " bytes";

    write_buf_.consume (bytes_transferred);
    if (write_buf_.size() == 0)
        return onRead (error_code(), 0);

    setTimer();
    stream_.async_write_some (write_buf_.data(),
        strand_.wrap (std::bind (&ConnectAttempt::onWrite,
            shared_from_this(), beast::asio::placeholders::error,
                beast::asio::placeholders::bytes_transferred)));
}

void
ConnectAttempt::onRead (error_code ec, std::size_t bytes_transferred)
{
    cancelTimer();

    if(! stream_.next_layer().is_open())
        return;
    if(ec == boost::asio::error::operation_aborted)
        return;
    if(ec == boost::asio::error::eof)
    {
        JLOG(journal_.info()) <<
            "EOF";
        setTimer();
        return stream_.async_shutdown(strand_.wrap(std::bind(
            &ConnectAttempt::onShutdown, shared_from_this(),
                beast::asio::placeholders::error)));
    }
    if(ec)
        return fail("onRead", ec);
    if(auto stream = journal_.trace())
    {
        if(bytes_transferred > 0)
            stream << "onRead: " << bytes_transferred << " bytes";
        else
            stream << "onRead";
    }

    if (! ec)
    {
        write_buf_.commit(bytes_transferred);
        auto bytes_consumed = parser_.write(
            write_buf_.data(), ec);
        if (! ec)
        {
            write_buf_.consume (bytes_consumed);
            if (parser_.complete())
                return processResponse(response_, body_);
        }
    }

    if (ec)
        return fail("onRead", ec);

    setTimer();
    stream_.async_read_some (write_buf_.prepare (Tuning::readBufferBytes),
        strand_.wrap (std::bind (&ConnectAttempt::onRead,
            shared_from_this(), beast::asio::placeholders::error,
                beast::asio::placeholders::bytes_transferred)));
}

void
ConnectAttempt::onShutdown (error_code ec)
{
    cancelTimer();
    if (! ec)
    {
        JLOG(journal_.error()) <<
            "onShutdown: expected error condition";
        return close();
    }
    if (ec != boost::asio::error::eof)
        return fail("onShutdown", ec);
    close();
}

//--------------------------------------------------------------------------

beast::deprecated_http::message
ConnectAttempt::makeRequest (bool crawl,
    boost::asio::ip::address const& remote_address)
{
    beast::deprecated_http::message m;
    m.method (beast::http::method_t::http_get);
    m.url ("/");
    m.version (1, 1);
    m.headers.insert ("User-Agent", BuildInfo::getFullVersionString());
    m.headers.insert ("Upgrade", "RTXP/1.2");
        //std::string("RTXP/") + to_string (BuildInfo::getCurrentProtocol()));
    m.headers.insert ("Connection", "Upgrade");
    m.headers.insert ("Connect-As", "Peer");
    m.headers.insert ("Crawl", crawl ? "public" : "private");
    return m;
}

template <class Streambuf>
void
ConnectAttempt::processResponse (beast::deprecated_http::message const& m,
    Streambuf const& body)
{
    if (response_.status() == 503)
    {
        Json::Value json;
        Json::Reader r;
        auto const success = r.parse(to_string(body), json);
        if (success)
        {
            if (json.isObject() && json.isMember("peer-ips"))
            {
                Json::Value const& ips = json["peer-ips"];
                if (ips.isArray())
                {
                    std::vector<boost::asio::ip::tcp::endpoint> eps;
                    eps.reserve(ips.size());
                    for (auto const& v : ips)
                    {
                        if (v.isString())
                        {
                            error_code ec;
                            auto const ep = parse_endpoint(v.asString(), ec);
                            if (!ec)
                                eps.push_back(ep);
                        }
                    }
                    overlay_.peerFinder().onRedirects(
                        remote_endpoint_, eps);
                }
            }
        }
    }

    if (! OverlayImpl::isPeerUpgrade(m))
    {
        JLOG(journal_.info()) <<
            "HTTP Response: " << m.status() << " " << m.reason();
        return close();
    }

    auto hello = parseHello (false, response_.headers, journal_);
    if(! hello)
        return fail("processResponse: Bad TMHello");

    auto sharedValue = makeSharedValue(
        ssl_bundle_->stream.native_handle(), journal_);
    if(! sharedValue)
        return close(); // makeSharedValue logs

    auto publicKey = verifyHello (*hello,
        *sharedValue,
        overlay_.setup().public_ip,
        beast::IPAddressConversion::from_asio(remote_endpoint_),
        journal_, app_);
    if(! publicKey)
        return close(); // verifyHello logs
    JLOG(journal_.info()) <<
        "Public Key: " << toBase58 (
            TokenType::TOKEN_NODE_PUBLIC,
            *publicKey);

    auto const protocol =
        BuildInfo::make_protocol(hello->protoversion());
    JLOG(journal_.info()) <<
        "Protocol: " << to_string(protocol);

    auto member = app_.cluster().member(*publicKey);
    if (member)
    {
        JLOG(journal_.info()) <<
            "Cluster name: " << *member;
    }

    auto const result = overlay_.peerFinder().activate (slot_,
        *publicKey, static_cast<bool>(member));
    if (result != PeerFinder::Result::success)
        return fail("Outbound slots full");

    auto const peer = std::make_shared<PeerImp>(app_,
        std::move(ssl_bundle_), read_buf_.data(),
            std::move(slot_), std::move(response_),
                usage_, *hello, *publicKey, id_, overlay_);

    overlay_.add_active (peer);
}

} // ripple
