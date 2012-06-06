require 'warden'
require 'omniauth'

class WardenOmniAuth
  DEFAULT_CALLBACK = lambda do |user|
    u = {}
    u[:info] = user['info']
    u[:uid] = user['uid']
    u[:credentials] = user['credentials']
    u[:provider] = user['provider']
    u
  end

  SCOPE_KEY        = 'warden_omni_auth.scope'
  SESSION_KEY      = 'rack.session'

  # Setup a callback to transform the user from the omni user hash
  # to what you want warden to store as the user object
  # @example
  #   WardenOmniAuth.on_callback do |omni_user|
  #     User.find_or_create_by_uid(omni_user['uid'])
  #   end
  def self.on_callback(&blk)
    @on_callback = blk if blk
    @on_callback || DEFAULT_CALLBACK
  end

  # Create a warden strategy to wrap an OmniAuth strategy
  # @param name - The name of the omniauth strategy
  # @example
  #   WardenOmniAuth.setup_strategies(:twitter, :facebook)
  def self.setup_strategies(*names)
    names.map do |name|
      full_name = :"omni_#{name}"
      unless Warden::Strategies[full_name]
        klass = Class.new(WardenOmniAuth::Strategy)
        klass.omni_name = name
        Warden::Strategies.add(full_name, klass)
      end
      Warden::Strategies[full_name]
    end
  end

  # The base omniauth warden strategy.  This is inherited for each
  # omniauth strategy
  class Strategy < Warden::Strategies::Base
    # make a specific callback for this strategy
    def self.on_callback(&blk)
      @on_callback = blk if blk
      @on_callback || WardenOmniAuth.on_callback
    end

    # The name of the OmniAuth strategy to map to
    def self.omni_name=(name)
      @omni_name = name
    end

    # The name of the OmniAuth strategy to map to
    def self.omni_name
      @omni_name
    end

    def authenticate!
      session = env[SESSION_KEY]
      session[SCOPE_KEY] = scope

      # set the user if one exists
      # otherwise, redirect for authentication
      if user = (env['omniauth.auth'] || env['rack.auth'] || request['auth']) # TODO: Fix..  Completely insecure... do not use this will look in params for the auth.  Apparently fixed in the new gem

        success! self.class.on_callback[user]
      else
        path_prefix = OmniAuth::Configuration.instance.path_prefix
        redirect! File.join(path_prefix, self.class.omni_name)
      end
    end
  end

  # Pulled from extlib
  # Convert to snake case.
  #
  #   "FooBar".snake_case           #=> "foo_bar"
  #   "HeadlineCNNNews".snake_case  #=> "headline_cnn_news"
  #   "CNN".snake_case              #=> "cnn"
  #
  # @return [String] Receiver converted to snake case.
  #
  # @api public
  def self.snake_case(string)
    return string.downcase if string.match(/\A[A-Z]+\z/)
    string.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
    gsub(/([a-z])([A-Z])/, '\1_\2').
    downcase
  end

  def initialize(app)
    # setup the warden strategies to wrap the omniauth ones
    names = OmniAuth::Strategies.constants.map do |konstant|
      name = WardenOmniAuth.snake_case(konstant.to_s)
    end
    WardenOmniAuth.setup_strategies(*names)
    yield self if block_given?
    @app = app
  end

  # redirect after a callback
  def redirect_after_callback=(path)
    @redirect_after_callback_path = path
  end


  def redirect_after_callback_path
    @redirect_after_callback_path ||= "/"
  end

  def call(env)
    request = Rack::Request.new(env)
    prefix = OmniAuth::Configuration.instance.path_prefix
    if request.path =~ /^#{prefix}\/(.+?)\/callback$/i
      strategy_name = $1
      strategy = Warden::Strategies._strategies.keys.detect{|k| k.to_s == "omni_#{strategy_name}"}

      if !strategy
        Rack::Response.new("Unknown Handler", 401).finish
      else
        # Warden needs to use a hashie for looking up scope
        # and strategy names
        session = env[SESSION_KEY]
        scope = session[SCOPE_KEY]
        if scope.nil? || scope.to_s.length < 100 # have to protect against symbols :(. need a hashie
          args = [strategy]
          args << {:scope => scope.to_sym} if scope
          response = Rack::Response.new
          if env['warden'].authenticate? *args
            response.redirect(redirect_after_callback_path)
            response.finish
          else
            auth_path = request.path.gsub(/\/callback$/, "")
            response.redirect(auth_path)
            response.finish
          end
        else
          Rack::Response.new("Bad Session", 400).finish
        end
      end
    else
      @app.call(env)
    end
  end
end
