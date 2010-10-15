$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")

require 'warden_omniauth'

Warden::Manager.serialize_into_session do |user|
  user
end

Warden::Manager.serialize_from_session do |user|
  user
end

app = lambda do |e|
  request = Rack::Request.new(e)
  if request.path =~ /logout/
    e['warden'].logout
    r = Rack::Response.new
    r.redirect("/")
    r.finish
  else
    e['warden'].authenticate!
    Rack::Response.new(e['warden'].user.inspect).finish
  end
end

failure = lambda{|e| Rack::Resposne.new("Can't login", 401).finish }

use Rack::Session::Cookie

use Warden::Manager do |config|
  config.failure_app = failure
  config.default_strategies :omni_twitter
end

use OmniAuth::Strategies::Twitter, key, sekrit
use WardenOmniAuth do |config|
  config.redirect_after_callback = "/foo/bar"
end


run app

