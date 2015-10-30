# oauth2rizer

A little OAuth2 helper library for JavaScript applications.

## Installation

Using [NPM][]

    npm install oauth2rizer

Using [Bower][]

    bower install oauth2rizer

## Usage

Include it (however) in your project, and create a new authorization function
with

```
auth = oauth2rizer(config)
```

Then use it when you need to make an authenticated request

``
auth().then(function(token) {
  accessSecretFile(token)
}
```

`config` is an object containing _at least_

* `client_id` - your app's client ID
* `client_secret` - your app's secret

It takes loads of other options, such as an array of scopes, an overrideable
XMLHttpRequest constructor (use XHR2 on Node), an overrideable Promise
constructor, redirect URLs - see the [source][].

If left to its own devices, it will authenticate with Google. You need to
pass different values for `auth_uri`, `token_uri` (and maybe `revoke_uri`) if
you want to use another provider, like Facebook.

The function, when called (with no arguments) returns a Promise which resolves
to an `access_token`. This token should then be sent along with your request
for the protected resource, in the Authorization header (`{Authorization:
"Bearer " + access_token}`).  This part is up to you - oauth2rizer functions
just get the `access_token`.

By default, it will get a refresh token, and store that in localStorage (if
available - on non browser environments, either configure the `remember`
function as a no-op, or pass in a compatible Storage object). Subsequent
requests will use this to refresh the access token.

## Authors

JJ (bjjb)

## License

ISC (see [LICENSE.txt][])

[NPM]: http://npmjs.com
[Bower]: http://bower.io
[source]: http://github.com/bjjb/oauth2rizer
[LICENSE.txt]: http://github.com/bjjb/oauth2rizer/LICENSE.txt
