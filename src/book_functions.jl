@inline function update_book!(book::OrderBook, ba::BidAsk)
    book.bba = ba
    return
end


@inline function fill_price(quantity::Volume, ob::OrderBook; zero_price=NaN)
    quantity > 0 ? ob.bba.ask : (quantity < 0 ? ob.bba.bid : zero_price)
end
