module FastbackParquet2Ext

import Fastback
import Parquet2

function Fastback.Artifacts.write_parquet_table(path::String, columns::NamedTuple)::Nothing
    temporary = path * ".tmp"
    Parquet2.writefile(temporary, columns; compression_codec=:snappy)
    mv(temporary, path; force=true)
    return nothing
end

end # module
