function update_book!(book::OrderBook{I}, ba::BidAsk) where {I}
    book.bba = ba
    return
end


function fill_price(quantity::Volume, ob::OrderBook{I}; zero_price=NaN) where {I}
    quantity > 0 ? ob.bba.ask : (quantity < 0 ? ob.bba.bid : zero_price)
end
