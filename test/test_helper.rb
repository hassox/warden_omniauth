require 'nanotest'
require 'nanotest/contexts'
require 'rack'
require 'rack/test'
include Nanotest
include Nanotest::Contexts

require 'warden_omniauth'

Warden::Manager.serialize_into_session do |user|
  user
end

Warden::Manager.serialize_from_session do |user|
  user
end

module MyHelpers
  def app
    @app || create_app{|e| Rack::Response.new("OK").finish }
  end

  def create_app(&blk)
    failure = lambda do |env|
      errors = env['warden'].errors.full_messages
      if errors.count > 0
        Rack::Response.new("Can't login: #{errors.join(',')}", 401).finish
      else
        Rack::Response.new("Can't login", 401).finish
      end
    end
    builder = Rack::Builder.new do
      use Warden::Manager do |config|
        config.failure_app = failure
        config.default_strategies :omni_twitter
      end

      #use OmniAuth::Strategies::Twitter, key, sekrit

      use WardenOmniAuth do |config|
        $omni_auth = config
        $expected_redirect = "/redirect/path"
        config.redirect_after_callback = $expected_redirect
      end
      run blk
    end.to_app
  end
end

