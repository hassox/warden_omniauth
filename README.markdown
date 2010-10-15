# Warden OmniAuth

OmniAuth is a pretty aweome library.  If you haven't checked it out yet, you really should. This is a simple wrapper for OmniAuth so that it can be used from a warden project.  It sorts storing the user into the sesion, redirection on callbacks etc.

With it, you can make use of any of the [OmniAuth](http://github.com/intridea/omniauth) authentication library.  This provides some great external authentication mechanisms.

Warden provides a consistent interface for projects, engines, and arbitrary rack applicaitons.  The benefit of warden, is that you do no need to know what the host application considers authentication to use it.  It also provides a way to store the user in the session etc.

By using WardenOmniAuth, you can make use of any of the OmniAuth authentication mechanisms in your host application, and any rack middleware or applications can just continue using warden without change.

This is also usable in the [Devise](http://github.com/plataformatec/devise) Rails Engine
## Usage (Rack)

<pre><code>use OmniAuth::Builer do
  # setup omniauth
end

use Warden::Manager do |config|
  # setup warden configuration
end

use WardenOmniAuth do |config|
  config.redirect\_after\_callback = "/redirect/path" # default "/"
end

run MyApp
</code></pre>

## Usage (Devise)

<pre><code># config/initializer.rb
Devise.setup do |config|
config.warden do |manager|
  [:omni\_twitter, :omni\_facebook, :omni\_github].each do |strategy|
    manager.default\_strategies(:scope => :user).unshift strategy
  end
end
</code></pre>

This will add the stratgeies to the normal devise user login for github, then facebook, then twitter.

# Dealing with callbacks

OmniAuth uses callbacks to give you the user object, WardenOmniAuth provides a way to store this into the session

By default, it grabs just _user\\info_, _uid_, _credentials_, _provider_ as a hash in the session.

If you want to customise this you can do:

<pre><code>
  WardenOmniAuth.on\_callback do |user|
    # all callbacks will go here by default
  end
</code></pre>

Whatever you return from the block is the user that's made available in warden.

## Dealing with each kind of callback

<pre><code>
use WardenOmniAuth do |config|
  Warden::Strategies[:omni\_twitter] do |user|
    # do stuff to get a user and return it from the block
  end

  Warden::Strategies[:omni\_facebook] do |user|
    # do stuff to get a user for a facebook user
  end
end
</code></pre>

This will use a specific callback to get the user, or fallback if nothing specific has been defined.


# Why? (Gimmie an alternative)

Because I wanted to see how it would be to integrate this strategy into warden.  Turns out to be pretty simple, but there's nothing stopping you from just providing a callback directly for OmniAuth.

However, it's just as simple to provide endpoints for OmniAuth callbacks. (Assuming you already have warden setup in your app)

Example:

<pre><code>
  get "/auth/twitter/callback" do
    user = munge_user_from_env(env['rack.auth'])
    warden.set_user user
    redirect "/somewhere"
  end
</code></pre>

You can see from this small snippet, that you don't really need this library, just define your callbacks to set the user and you're done.

Rack is a beutiful thing!
