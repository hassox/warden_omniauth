require 'test/test_helper'
require 'omniauth-twitter'
require 'omniauth-facebook'
require 'omniauth-google-oauth2'

# WardenOmniauth
context do
  include Rack::Test::Methods
  include MyHelpers
  teardown { @_rack_mock_sessions = nil; @_rack_test_sessions = nil  }

  # should setup all the omni auth strategies
  test do
    app
    OmniAuth::Strategies.constants.each do |klass|
      name = OmniAuth::Strategies.const_get(klass).new(nil).name
      assert { Warden::Strategies[:"omni_#{name}"] != nil }
      assert { Warden::Strategies[:"omni_#{name}"].superclass == WardenOmniAuth::Strategy }
    end
  end

  # test the middleware in a request
  context do
    setup do
      @app = create_app do |e|
        request = Rack::Request.new(e)
        Rack::Response.new(request.path).finish
      end
    end
    teardown { @_rack_mock_sessions = nil; @_rack_test_sessions = nil  }

    # test that any non /auth urls fall through to the app
    test do
      response = get "/foo", {}, {'rack.session' => {}}
      assert { response.status == 200       }
      assert { response.body.to_s == "/foo" }
    end

    # anything going to /auth/<strategy> should fall through to omniauth (the app)
    test do
      response = get "/auth/twitter", {}, {'rack.session' => {}}
      assert { response.status == 200                }
      assert { response.body.to_s == "/auth/twitter" }
    end

    # the callback url should be intercepted and should raise if it's unknown
    test do
      assert { Warden::Strategies[:omni_does_not_exist].nil? }
      response = get "/auth/does_not_exist/callback", {}, {'rack.session' => {}}
      assert("status should be 401"       ) { response.status == 401              }
      assert("text should be Can't login" ) { response.body.to_s == "Can't login" }
    end

    # the callback url should be intercepted and should redirect back to the strategy if there is no user
    # in rack['auth']
    test do
      response = get "/auth/twitter/callback", {}, { 'omniauth.auth' => nil, 'rack.session' => {}}
      assert("status should be 302") { response.status == 302 }
      assert("url should be /auth/twitter") { response.headers['Location'] == '/auth/twitter' }
    end

    # The session scope should not be too big
    test do
      session = {}
      session[WardenOmniAuth::SCOPE_KEY] = "a" * 101

      response = get "/auth/twitter/callback", {}, {'rack.session' => session }
      assert("status should be 400"      ) { response.status    == 400           }
      assert("body should be bad status" ) { response.body.to_s == "Bad Session" }
    end

    # The failure app should run if OmniAuth indicates a failure
    test do
      response = get "/auth/failure", {:strategy => 'twitter', :message => 'Things went south!'}, {'rack.session' => {} }
      assert("status should be 401") { response.status == 401 }
      assert("text should include 'Can't login'") { response.body.include? "Can't login" }
      assert("text should include OmniAuth's failure message") { response.body.include? "Things went south!" }
    end
  end

  context do
    teardown { @_rack_mock_sessions = nil; @_rack_test_sessions = nil  }
    setup do
      $captures = []
      @app = create_app do |e|
        e['warden'].authenticate
        $captures << e['warden'].user
        Rack::Response.new("DONE").finish
      end
    end

    # The callback should also work as a lambda
    test do
      session = {}
      $omni_auth.redirect_after_callback do |env|
        assert("passed env should have omniauth.auth key") { env.has_key? 'omniauth.auth' }
        "/path/to/#{env['omniauth.auth']['info']}"
      end

      response = get("/auth/twitter/callback", {}, {'rack.session' => session, 'omniauth.auth' => {'info' => "alice"}})

      assert("should be redirected") { response.status == 302 }
      assert("should go to the redirect path"){ response.headers['Location'] == "/path/to/alice" }

      response = get("/path/to/alice", {}, {'rack.session' => session })
      assert("should have made it into the app") { $captures.size == 1 }
      assert("should have captured the user"){ $captures.first[:info] == 'alice' }
    end
  end

  context do
    teardown { @_rack_mock_sessions = nil; @_rack_test_sessions = nil  }
    setup do
      $captures = []
      @app = create_app do |e|
        e['warden'].authenticate
        $captures << e['warden'].user(:user)
        Rack::Response.new("DONE").finish
      end
    end

    # The session scope should store the user
    test do
      session = {}
      session[WardenOmniAuth::SCOPE_KEY] = "user"

      response = get("/auth/twitter/callback", {}, {'rack.session' => session, 'omniauth.auth' => {'info' => "fred"}})

      assert("should be redirected") { response.status == 302 }
      assert("should go to the redirect path"){ response.headers['Location'] == $expected_redirect }

      response = get($expected_redirect, {}, {'rack.session' => session })
      assert("should have made it into the app") { $captures.size == 1 }
      assert("should have captured the user"){ $captures.first[:info] == 'fred' }
    end

    # should give me different handlers for different callbacks
    test do
      begin
        session = {}
        session[WardenOmniAuth::SCOPE_KEY] = "user"

        Warden::Strategies[:omni_facebook].on_callback do |user,strategy|
          {:facebook => "user"}
        end
        Warden::Strategies[:omni_twitter].on_callback do |user,strategy|
          {:twitter => "user"}
        end
        Warden::Strategies[:omni_google_oauth2].on_callback do |user,strategy|
          {:google_oauth2 => "user"}
        end

        response = get("/auth/facebook/callback", {}, {'rack.session' => session, 'omniauth.auth' => {'info' => "fred"}})
        response = get $expected_redirect, {}, {'rack.session' => session}
        assert { $captures.size == 1 }
        assert { $captures.first == {:facebook => "user"} }
        $captures = []

        session = {}
        session[WardenOmniAuth::SCOPE_KEY] = "user"
        response = get("/auth/twitter/callback", {}, {'rack.session' => session, 'omniauth.auth' => {'info' => 'fred'}})
        response = get $expected_redirect, {}, {'rack.session' => session}
        assert { $captures.size == 1 }
        assert { $captures.first == {:twitter => "user"} }
        $captures = []

        session = {}
        session[WardenOmniAuth::SCOPE_KEY] = "user"
        response = get("/auth/google_oauth2/callback", {}, {'rack.session' => session, 'omniauth.auth' => {'info' => 'fred'}})
        response = get $expected_redirect, {}, {'rack.session' => session}
        assert { $captures.size == 1 }
        assert { $captures.first == {:google_oauth2 => "user"} }
      ensure
        Warden::Strategies[:omni_facebook].on_callback &WardenOmniAuth::DEFAULT_CALLBACK
        Warden::Strategies[:omni_twitter].on_callback &WardenOmniAuth::DEFAULT_CALLBACK
        Warden::Strategies[:omni_google_oauth2].on_callback &WardenOmniAuth::DEFAULT_CALLBACK
      end
    end

  end
end
