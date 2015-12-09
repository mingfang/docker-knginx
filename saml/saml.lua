local cjson = require("cjson")
local xml = require("xml")
local inspect = require("inspect")

local ngx_var = ngx.var
local saml = {}

local saml_idp_url = os.getenv("SAML_IDP_URL")
local secret = os.getenv("SESSION_SECRET")
local profileLocation = os.getenv("PROFILE_LOCATION")

-- call with access_by_lua 'require("saml").checkAccess()';
function saml.checkAccess()
    local session = require "resty.session".open()

    -- no session, redirect to idp
    if not session.data.nameId then
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
    local args, err = ngx.req.get_post_args()
    if not args then
        ngx.log(ngx.ERR, "failed to get post args: ", err)
        ngx.exit(400)
    end

    -- parse XML
    local samlResponseXML = ngx.decode_base64(args.SAMLResponse)
    local samlResponse = xml.load(samlResponseXML)
    xml.removeNamespace(samlResponse, "urn:oasis:names:tc:SAML:2.0:protocol")
    xml.removeNamespace(samlResponse, "urn:oasis:names:tc:SAML:2.0:assertion")

    -- start session
    local session = require "resty.session".start()
    if secret then
        session.secret = secret
    end
    session.data.nameId = xml.find(samlResponse, "NameID")[1]
    session.data.status = xml.find(samlResponse, "StatusCode").Value

    -- store assertions
    local assertions = xml.find(samlResponse, "AttributeStatement")
    if assertions then
      for key, val in pairs(assertions) do
          if type(val) == "table" then
            -- todo: may need to decrypt
            session.data[val.Name] = val[1][1]
          end
      end
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
            -- ngx.log(ngx.ERR, inspect(profile))
            for key, val in pairs(profile) do
                session.data[key] = val
            end
        else
            -- problem with profile, clean up and exit
            ngx.log(ngx.ERR, "Error loading profile for: "..session.data.nameId.." status:"..res.status)
            session:destroy()
            ngx.exit(500)
        end
    end

    -- session is good
    session:save()
    ngx.log(ngx.ERR, "login: "..session.data.nameId)

    -- redirect to RelayState
    local relayState = args.RelayState
    if (relayState ~= nill and relayState ~= "") then
      return ngx.redirect(relayState)
    else
      return ngx.exit(200)
    end
end

-- destroy session
function saml.logout()
    local session = require "resty.session".open()
    if session.data.nameId then
        ngx.log(ngx.ERR, "logout: "..session.data.nameId)
    end

    session:destroy()
    return ngx.exit(200)
end

return saml
