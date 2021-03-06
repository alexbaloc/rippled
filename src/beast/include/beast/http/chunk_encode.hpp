//
// Copyright (c) 2013-2016 Vinnie Falco (vinnie dot falco at gmail dot com)
//
// Distributed under the Boost Software License, Version 1.0. (See accompanying
// file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
//

#ifndef BEAST_HTTP_CHUNK_ENCODE_HPP
#define BEAST_HTTP_CHUNK_ENCODE_HPP

#include <boost/asio/buffer.hpp>
#include <algorithm>
#include <array>
#include <cassert>
#include <cstddef>
#include <iterator>
#include <type_traits>

namespace beast {
namespace http {

namespace detail {

template <class Buffers>
class chunk_encoded_buffers
{
private:
    using const_buffer = boost::asio::const_buffer;

    Buffers buffers_;
    const_buffer head_;
    const_buffer tail_;

    // Storage for the longest hex string we might need, plus delimiters.
    std::array<char, 2 * sizeof(std::size_t) + 2> data_;

public:
    using value_type = boost::asio::const_buffer;

    class const_iterator;

    chunk_encoded_buffers() = delete;
    chunk_encoded_buffers (chunk_encoded_buffers const&) = default;
    chunk_encoded_buffers& operator= (chunk_encoded_buffers const&) = default;

    chunk_encoded_buffers (Buffers const& buffers, bool final_chunk);

    const_iterator
    begin() const
    {
        return const_iterator(*this, false);
    }

    const_iterator
    end() const
    {
        return const_iterator(*this, true);
    }

private:
    // Unchecked conversion of unsigned to hex string
    template<class OutIter, class Unsigned>
    static
    typename std::enable_if<
        std::is_unsigned<Unsigned>::value, OutIter>::type
    to_hex(OutIter const first, OutIter const last, Unsigned n);
};

template <class Buffers>
class chunk_encoded_buffers<Buffers>::const_iterator
    : public std::iterator<std::bidirectional_iterator_tag, const_buffer>
{
private:
    using iterator = typename Buffers::const_iterator;
    enum class Where { head, input, end };
    chunk_encoded_buffers const* buffers_;
    Where where_;
    iterator iter_;

public:
    const_iterator();
    const_iterator (const_iterator const&) = default;
    const_iterator& operator= (const_iterator const&) = default;
    bool operator== (const_iterator const& other) const;
    bool operator!= (const_iterator const& other) const;
    const_iterator& operator++();
    const_iterator& operator--();
    const_iterator operator++(int) const;
    const_iterator operator--(int) const;
    const_buffer operator*() const;

private:
    friend class chunk_encoded_buffers;
    const_iterator(chunk_encoded_buffers const& buffers, bool past_the_end);
};

//------------------------------------------------------------------------------

template <class Buffers>
chunk_encoded_buffers<Buffers>::chunk_encoded_buffers (
        Buffers const& buffers, bool final_chunk)
    : buffers_(buffers)
{
    auto const size = boost::asio::buffer_size(buffers);
    data_[data_.size() - 2] = '\r';
    data_[data_.size() - 1] = '\n';
    auto pos = to_hex(data_.begin(), data_.end() - 2, size);
    head_ = const_buffer(&*pos,
        std::distance(pos, data_.end()));
    if (size > 0 && final_chunk)
        tail_ = const_buffer("\r\n0\r\n\r\n", 7);
    else
        tail_ = const_buffer("\r\n", 2);
}

template <class Buffers>
template <class OutIter, class Unsigned>
typename std::enable_if<
    std::is_unsigned<Unsigned>::value, OutIter>::type
chunk_encoded_buffers<Buffers>::to_hex(
    OutIter const first, OutIter const last, Unsigned n)
{
    assert(first != last);
    OutIter iter = last;
    if(n == 0)
    {
        *--iter = '0';
        return iter;
    }
    while(n)
    {
        assert(iter != first);
        *--iter = "0123456789abcdef"[n&0xf];
        n>>=4;
    }
    return iter;
}

template <class Buffers>
chunk_encoded_buffers<Buffers>::const_iterator::const_iterator()
    : buffers_(nullptr)
    , where_(Where::end)
{
}

template <class Buffers>
bool
chunk_encoded_buffers<Buffers>::const_iterator::operator==(
    const_iterator const& other) const
{
    return buffers_ == other.buffers_ &&
        where_ == other.where_ && iter_ == other.iter_;
}

template <class Buffers>
bool
chunk_encoded_buffers<Buffers>::const_iterator::operator!=(
    const_iterator const& other) const
{
    return buffers_ != other.buffers_ ||
        where_ != other.where_ || iter_ != other.iter_;
}

template <class Buffers>
auto
chunk_encoded_buffers<Buffers>::const_iterator::operator++() ->
    const_iterator&
{
    assert(buffers_);
    assert(where_ != Where::end);
    if (where_ == Where::head)
        where_ = Where::input;
    else if (iter_ != buffers_->buffers_.end())
        ++iter_;
    else
        where_ = Where::end;
    return *this;
}

template <class Buffers>
auto
chunk_encoded_buffers<Buffers>::const_iterator::operator--() ->
    const_iterator&
{
    assert(buffers_);
    assert(where_ != Where::head);
    if (where_ == Where::end)
        where_ = Where::input;
    else if (iter_ != buffers_->buffers_.begin())
        --iter_;
    else
        where_ = Where::head;
    return *this;
}

template <class Buffers>
auto
chunk_encoded_buffers<Buffers>::const_iterator::operator++(int) const ->
    const_iterator
{
    auto iter = *this;
    ++iter;
    return iter;
}

template <class Buffers>
auto
chunk_encoded_buffers<Buffers>::const_iterator::operator--(int) const ->
    const_iterator
{
    auto iter = *this;
    --iter;
    return iter;
}

template <class Buffers>
auto
chunk_encoded_buffers<Buffers>::const_iterator::operator*() const ->
    const_buffer
{
    assert(buffers_);
    assert(where_ != Where::end);
    if (where_ == Where::head)
        return buffers_->head_;
    if (iter_ != buffers_->buffers_.end())
        return *iter_;
    return buffers_->tail_;
}

template <class Buffers>
chunk_encoded_buffers<Buffers>::const_iterator::const_iterator(
        chunk_encoded_buffers const& buffers, bool past_the_end)
    : buffers_(&buffers)
    , where_(past_the_end ? Where::end : Where::head)
    , iter_(past_the_end ? buffers_->buffers_.end() :
        buffers_->buffers_.begin())
{
}

} // detail

/** Returns a chunk-encoded BufferSequence.

    See:
        http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.6.1

    @param buffers The input buffer sequence.

    @param final_chunk `true` If this should include a final-chunk.

    @return A chunk-encoded ConstBufferSequence representing the input.
*/
template<class ConstBufferSequence>
#if GENERATING_DOCS
implementation_defined
#else
detail::chunk_encoded_buffers<ConstBufferSequence>
#endif
chunk_encode(ConstBufferSequence const& buffers,
    bool final_chunk = false)
{
    return detail::chunk_encoded_buffers<
        ConstBufferSequence>{buffers, final_chunk};
}

/// Returns a chunked encoding final chunk.
inline
#if GENERATING_DOCS
implementation_defined
#else
boost::asio::const_buffers_1
#endif
chunk_encode_final()
{
    return boost::asio::const_buffers_1(
        "0\r\n\r\n", 5);
}

} // http
} // beast

#endif
