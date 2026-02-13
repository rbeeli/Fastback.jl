using Dates
using TestItemRunner

@testitem "Cash/Instrument/Position hashing works with Dict" begin
    using Test, Fastback, Dates

    cash = Cash(1, :USD, 2)
    @test hash(cash) isa UInt
    cash_dict = Dict{Cash,Int}()
    cash_dict[cash] = 1
    @test cash_dict[cash] == 1

    inst = spot_instrument(Symbol("HASH/USD"), :HASH, :USD)
    inst.index = 1
    @test hash(inst) isa UInt
    inst_dict = Dict{typeof(inst),Int}()
    inst_dict[inst] = 2
    @test inst_dict[inst] == 2

    pos = Position{DateTime}(1, inst)
    @test hash(pos) isa UInt
    pos_dict = Dict{Position{DateTime},Int}()
    pos_dict[pos] = 3
    @test pos_dict[pos] == 3
end
