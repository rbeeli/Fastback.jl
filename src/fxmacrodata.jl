module FXMacroData

using Downloads

export Client,
    data_catalogue,
    announcements,
    calendar,
    predictions,
    forex,
    cot,
    commodities_latest,
    commodity,
    curves,
    curve_proxies,
    forward_curves,
    market_sessions,
    risk_sentiment,
    news,
    press_releases,
    central_bankers,
    get_json

struct Client
    api_key::Union{Nothing,String}
    base_url::String
end

Client(api_key::Union{Nothing,String}=nothing; base_url::String="https://api.fxmacrodata.com/v1") =
    Client(api_key, rstrip(base_url, '/'))

data_catalogue(client::Client, currency::AbstractString) = get_json(client, "/data_catalogue/$(norm(currency))")
announcements(client::Client, currency::AbstractString, indicator::AbstractString) = get_json(client, "/announcements/$(norm(currency))/$indicator")
calendar(client::Client, currency::AbstractString) = get_json(client, "/calendar/$(norm(currency))")
predictions(client::Client, currency::AbstractString, indicator::AbstractString) = get_json(client, "/predictions/$(norm(currency))/$indicator")
forex(client::Client, base::AbstractString, quote::AbstractString) = get_json(client, "/forex/$(norm(base))/$(norm(quote))")
cot(client::Client, currency::AbstractString) = get_json(client, "/cot/$(norm(currency))")
commodities_latest(client::Client) = get_json(client, "/commodities/latest")
commodity(client::Client, indicator::AbstractString) = get_json(client, "/commodities/$indicator")
curves(client::Client, currency::AbstractString) = get_json(client, "/curves/$(norm(currency))")
curve_proxies(client::Client, currency::AbstractString) = get_json(client, "/curve_proxies/$(norm(currency))")
forward_curves(client::Client, currency::AbstractString) = get_json(client, "/forward_curves/$(norm(currency))")
market_sessions(client::Client) = get_json(client, "/market_sessions")
risk_sentiment(client::Client) = get_json(client, "/risk_sentiment")
news(client::Client, currency::AbstractString) = get_json(client, "/news/$(norm(currency))")
press_releases(client::Client, currency::AbstractString) = get_json(client, "/press-releases/$(norm(currency))")
central_bankers(client::Client, currency::AbstractString) = get_json(client, "/central_bankers/$(norm(currency))")

function get_json(client::Client, path::AbstractString; query::Dict{String,String}=Dict{String,String}())
    url = build_url(client, path, query)
    io = IOBuffer()
    Downloads.download(url, io)
    return String(take!(io))
end

function build_url(client::Client, path::AbstractString, query::Dict{String,String})
    params = copy(query)
    if client.api_key !== nothing && !isempty(client.api_key)
        params["api_key"] = client.api_key
    end
    suffix = isempty(params) ? "" : "?" * join(["$(escape_component(k))=$(escape_component(v))" for (k, v) in params], "&")
    return client.base_url * path * suffix
end

norm(value::AbstractString) = lowercase(strip(String(value)))

function escape_component(value::AbstractString)
    out = IOBuffer()
    for byte in codeunits(String(value))
        if (byte >= UInt8('a') && byte <= UInt8('z')) ||
           (byte >= UInt8('A') && byte <= UInt8('Z')) ||
           (byte >= UInt8('0') && byte <= UInt8('9')) ||
           byte in UInt8[UInt8('-'), UInt8('_'), UInt8('.'), UInt8('~')]
            write(out, byte)
        else
            print(out, "%", uppercase(string(byte, base=16, pad=2)))
        end
    end
    return String(take!(out))
end

end
