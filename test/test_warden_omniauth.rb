require 'test/test_helper'
require 'omniauth-twitter'
require 'omniauth-facebook'

# WardenOmniauth
context do
  include Rack::Test::Methods
  include MyHelpers
  teardown { @_rack_mock_sessions = nil; @_rack_test_sessions = nil  }

  # shoudl setup all the omni auth strategies
  test do
    app
    OmniAuth::Strategies.constants.each do |klass|
      name = WardenOmniAuth.snake_case(klass.to_s)
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

    # the callback url shoudl be intercepted and  should raise if it's unknown
    test do
      assert { Warden::Strategies[:omni_does_not_exist].nil? }
      response = get "/auth/does_not_exist/callback", {}, {'rack.session' => {}}
      assert("status should be 401"       ) { response.status == 401              }
      assert("text should be Can't login" ) { response.body.to_s == "Can't login" }
    end

    # the callback url should be intercepted and should redirect back to the strategy if there is no user
    # in rack['auth']
    test do
      response = get "/auth/twitter/callback", {}, { 'rack.auth' => nil, 'rack.session' => {}}
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
      expected_redirect = $omni_auth.redirect_after_callback_path

      response = get("/auth/twitter/callback", {}, {'rack.session' => session, 'rack.auth' => {'user_info' => "fred"}})

      assert("should be redirected") { response.status == 302 }
      assert("should go to the redirect path"){ response.headers['Location'] == expected_redirect }

      response = get(expected_redirect, {}, {'rack.session' => session })
      assert("should have made it into the app") { $captures.size == 1 }
      assert("should have captured the user"){ $captures.first[:user_info] == 'fred' }
    end

    # should give me different handlers for different callbacks
    test do
      begin
        session = {}
        session[WardenOmniAuth::SCOPE_KEY] = "user"
        expected_redirect = $omni_auth.redirect_after_callback_path

        Warden::Strategies[:omni_facebook].on_callback do |user|
          {:facebook => "user"}
        end
        Warden::Strategies[:omni_twitter].on_callback do |user|
          {:twitter => "user"}
        end

        response = get("/auth/facebook/callback", {}, {'rack.session' => session, 'rack.auth' => {'user_info' => "fred"}})
        response = get expected_redirect, {}, {'rack.session' => session}
        assert { $captures.size == 1 }
        assert { $captures.first == {:facebook => "user"} }
        $captures = []

        session = {}
        session[WardenOmniAuth::SCOPE_KEY] = "user"
        response = get("/auth/twitter/callback", {}, {'rack.session' => session, 'rack.auth' => {'user_info' => 'fred'}})
        response = get expected_redirect, {}, {'rack.session' => session}
        assert { $captures.size == 1 }
        assert { $captures.first == {:twitter => "user"} }
      ensure
        Warden::Strategies[:omni_facebook].on_callback &WardenOmniAuth::DEFAULT_CALLBACK
        Warden::Strategies[:omni_twitter ].on_callback &WardenOmniAuth::DEFAULT_CALLBACK
      end
    end

  end
end
