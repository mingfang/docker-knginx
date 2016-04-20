var logger = require('log4js').getLogger('authenticator')

var config = require('config')
logger.info('config', config)

var passportsaml = require('passport-saml')
var saml = new passportsaml.SAML(config.saml)

var express = require('express');
var bodyParser   = require( 'body-parser' );

var app = express();
app.use(bodyParser.urlencoded({extended: false}));

app.post('*', function (req, res) {
  logger.info(req.url)
  saml.validatePostResponse(req.body, function(err, profile){
    if(err){
      logger.warn(err)
      res.sendStatus(403)
    }else{
      // remove unwanted keys
      delete profile['issuer']
      delete profile['sessionIndex']
      delete profile['nameIDFormat']
      delete profile['getAssertionXml']
      
      logger.info(profile)
      res.json(profile)
    }
  })
});

var server = app.listen(config.port, function () {
    var host = server.address().address;
    var port = server.address().port;
    logger.info('Listening %s:%s', host, port);
});
