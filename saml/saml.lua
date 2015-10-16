local ngx_var      = ngx.var

local saml = {}

-- call with access_by_lua 'require("saml").checkAccess()';
function saml.checkAccess()
    local session = require "resty.session".open()
    -- no session, redirect to idp
    if not session.data.nameId then
        local saml_idp_url = os.getenv("SAML_IDP_URL")
        local relay_state = ngx_var.scheme.."://"..ngx.req.get_headers().host..ngx_var.uri
        local redirect_url = saml_idp_url.."?RelayState="..relay_state
        ngx.log(ngx.ERR, "redirect to idp:"..redirect_url)
        return ngx.redirect(redirect_url)
    end
    -- has session, enrich request with session data
    for key, value in pairs(session.data) do
        ngx.req.set_header(key, value)
    end
end

-- called by IdP after login, POST SAMLResponse and RelayState
function saml.acs()
    ngx.req.read_body()
    local args, err = ngx.req.get_post_args()
    if not args then
        ngx.say("failed to get post args: ", err)
        return
    end
    local samlResponseXML = ngx.decode_base64(args.SAMLResponse)
    -- ngx.say("Decoded SAMLResponse XML:", samlResponseXML)

    local xml = require("xml")
    local samlResponse = xml.load(samlResponseXML)
    xml.removeNamespace(samlResponse, "urn:oasis:names:tc:SAML:2.0:protocol")
    xml.removeNamespace(samlResponse, "urn:oasis:names:tc:SAML:2.0:assertion")
    -- ngx.say("cleaned", xml.dump(samlResponse))

    -- start session and store all assertions
    local session = require "resty.session".start()
    if os.getenv("SESSION_SECRET") then
        session.secret = os.getenv("SESSION_SECRET")
    end
    session.data.nameId = xml.find(samlResponse, "NameID")[1]
    session.data.status = xml.find(samlResponse, "StatusCode").Value

    local assertions = xml.find(samlResponse, "AttributeStatement")
    if assertions then
      for key, val in pairs(assertions) do
          if type(val) == "table" then
            -- todo: may need to decrypt
            session.data[val.Name] = val[1][1]
          end
      end
    end

    -- todo: load external session data
        
    session:save()

    local relayState = args.RelayState
    -- ngx.log(ngx.ERR, "acs relayState"..relayState)

    if (relayState ~= nill and relayState ~= "") then
      return ngx.redirect(relayState)
    else
      -- todo: this is not a good idea    
      return ngx.redirect("/saml/echo")
    end
end

function saml.logout()
    local session = require "resty.session".start()
    session:destroy()
end

return saml
