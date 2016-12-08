local cjson = require("cjson")
local inspect = require("inspect")

local ngx_var = ngx.var
local saml = {}

local saml_idp_url = os.getenv("SAML_IDP_URL")
local secret = os.getenv("SESSION_SECRET") or "secret123"
local profileLocation = os.getenv("PROFILE_LOCATION")
local logoutLocation = os.getenv("LOGOUT_LOCATION")

-- call with access_by_lua 'require("saml").checkAccess()';
function saml.checkAccess()
    local session = require "resty.session".open{ secret = secret }

    -- no session, redirect to idp
    if not session.data.nameID then
        local relay_state = ngx_var.scheme.."://"..ngx.req.get_headers().host..ngx_var.uri
        local redirect_url = saml_idp_url.."?RelayState="..relay_state
        -- ngx.log(ngx.ERR, "redirect to idp:"..redirect_url)
        return ngx.redirect(redirect_url)
    end

    -- enrich request with session data
    for key, value in pairs(session.data) do
        ngx.req.set_header(key, value)
    end
end

-- called by IdP after login, POST SAMLResponse and RelayState
function saml.acs()
    ngx.req.read_body()
    ngx.log(ngx.INFO, ngx.var.request_body)

    local http = require "resty.http"
    local httpc = http.new()

    local res, err = httpc:request_uri("http://127.0.0.1:3000/saml/validatePostResponse",{
       method = "POST",
       body = ngx.var.request_body,
       headers = {
         ["Content-Type"] = "application/x-www-form-urlencoded"
       }
    })
    httpc:set_keepalive()

    -- ngx.log(ngx.INFO, "res status: ", res.status)
    -- ngx.log(ngx.INFO, "res.headers: ", inspect(res))
    if res.status ~= 200 then
        ngx.log(ngx.INFO, "SAML Auth Failed")
        ngx.exit(403)
    end

    -- start session
    local session = require "resty.session".start{ secret = secret }

    -- store assertions
    local assertions = cjson.decode(res.body)
    -- ngx.log(ngx.INFO, inspect(assertions))
    for key, val in pairs(assertions) do
        session.data[ngx.escape_uri(key)] = val
    end

    -- load external session data
    if profileLocation then
        -- enrich request with session data
        for key, value in pairs(session.data) do
            ngx.req.set_header(key, value)
        end
        -- load profile
        local res = ngx.location.capture(profileLocation)
        if res.status == 200 then
            local profile = cjson.decode(res.body)
            -- ngx.log(ngx.INFO, inspect(profile))
            for key, val in pairs(profile) do
                session.data[ngx.escape_uri(key)] = val
            end
            -- set cookie if any
            if res.header['Set-Cookie'] then
               ngx.header['Set-Cookie'] = res.header['Set-Cookie']
               ngx.log(ngx.INFO, session.data.nameID..": Set-Cookie: "..res.header['Set-Cookie'])
            end
        else
            -- problem with profile, clean up and exit
            ngx.log(ngx.ERR, "Error loading profile for: "..session.data.nameID.." status:"..res.status)
            session:destroy()
            ngx.exit(403)
        end
    end

    -- session is good
    session:save()
    ngx.log(ngx.INFO, "login: "..session.data.nameID)

    -- redirect to RelayState
    local args, err = ngx.req.get_post_args()
    local relayState = args.RelayState
    if (relayState ~= nill and relayState ~= "") then
      return ngx.redirect(relayState)
    else
      return ngx.exit(200)
    end
end

-- destroy session
function saml.logout()
    local session = require "resty.session".open{ secret = secret }
    if session.data.nameID then
        ngx.log(ngx.INFO, "logout: "..session.data.nameID)
    end

    if logoutLocation then
        -- enrich request with session data
        for key, value in pairs(session.data) do
            ngx.req.set_header(key, value)
        end
        local res = ngx.location.capture(logoutLocation)
        ngx.log(ngx.INFO, logoutLocation.." "..res.status)
    end

    session:destroy()
    return ngx.exit(200)
end

return saml
