module FastbackParquet2Ext

import Fastback
import Parquet2

function Fastback.Artifacts.write_parquet_table(path::String, columns::NamedTuple)::Nothing
    temporary = path * ".tmp"
    Parquet2.writefile(temporary, columns; compression_codec=:snappy)
    mv(temporary, path; force=true)
    return nothing
end

mutable struct ParquetStream
    path::String
    temporary::String
    io::IOStream
    writer::Parquet2.FileWriter{IOStream}
end

function Fastback.Artifacts.open_parquet_stream(path::String)::ParquetStream
    temporary = path * ".tmp"
    io = open(temporary, "w")
    return ParquetStream(path, temporary, io, Parquet2.FileWriter(io, temporary; compression_codec=:snappy))
end

function Fastback.Artifacts.write_parquet_batch!(stream::ParquetStream, columns::NamedTuple)::Nothing
    Parquet2.writetable!(stream.writer, columns)
    return nothing
end

function Fastback.Artifacts.close_parquet_stream!(stream::ParquetStream)::Nothing
    Parquet2.finalize!(stream.writer)
    close(stream.io)
    mv(stream.temporary, stream.path; force=true)
    return nothing
end

end # module
