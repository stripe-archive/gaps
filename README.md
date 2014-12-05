# Gaps

Easy management of your Google Apps email configuration.

# Overview

At Stripe, we've long had many
[more Google Group mailing lists than employees](https://stripe.com/blog/email-transparency). As
the number of lists grew, so too did the complexity of managing your
email setup: which lists were you on? Why are you receiving email for
this list you're not subscribed to? How do you set up your filters to
usually archive email to a list, but only if you're not present on the
CC?

Gaps is the main tool we've used to help make these questions
manageable. The core functionality is surprisingly simple: a single
list of all your Google Groups in one place, which lets you view your
subscriptions (including whether you're receiving mail from a list
being subscribed to another list), and subscribe or unsubscribe by the
click of a button.

More recently, we've also added filter generation and
maintenance. Unfortunately Google's email settings API only allows you
to create new filters, so it's up to the user to delete their old
ones.

# What it looks like

![Gaps](https://www.dropbox.com/s/x9y1tus9x2myjey/gaps.png?dl=1)

# Configuring

Create a `site.yaml` with your local settings: `cp site.yaml.sample
site.yaml`. You'll need:

- A Google application. See instructions below, and then update
  `site.yaml`.
- A running MongoDB instance. Gaps stores some soft state (cache of
  what it gets out of the API), but also has some hard state (the
  categorization of your groups, people's filter settings). Update
  `site.yaml` appropriately.
- (At runtime) an admin account on your Google Apps domain.

## Creating a Google application

1. Make sure you have
  [API access](https://support.google.com/a/answer/60757?hl=en)
  enabled for your Google Apps domain.
2. Create a
   [new project](https://console.developers.google.com/project).
3. Under the "APIs & auth" accordian for that project, select the
   "APIs" tab. Enable the Google+ API and Admin SDK.
4. Under the same accordian, select the "Credentials" tab. Create a
   new "Web application" Client ID. Add your desired redirect URI and
   authorized origins. (In development that'll probably be
   `http://localhost:3500` and `http://localhost:3500/oauth2callback`,
   respectively.)
5. Copy your client ID and client secret into your `site.yaml` file.

# Running

You can run Gaps directly or under Docker.

## Running directly

Run `bundle install` to install your dependencies. Gaps should run on
Ruby 1.9 and up. Then execute `bin/gaps_server.rb` (or
`bin/dev-runner` if you want auto-reloading upon code changes).

## Running under Docker

Because there are a lot of settings, running under Docker requires a
configuration file. Clone this repository and execute
`bin/docker-runner` to run the Docker image we've published with your
`site.yaml` bind-mounted inside.

# Permissions

Gaps uses your domain admin's credentials to perform most actions
(listing all groups, joining a group), so by default you can see and
join any group independent of their Google permissions.

Private lists can be created by one of three ways:

- Prefixing the name with `private-`.
- Prefixing the name with the less-cumbersome but more-obscure `acl-`.
- Adding a JSON tag as the last line of the group description with a
  "display" setting as follows: `{"display": "none"}`

These will be omitted from the directory listing, won't be emailed
about, and users won't be able to join them.

# Contributions

Patches welcome! There are many features that would be useful that
Gaps doesn't yet support. For example:

- Managing your group settings: generally you probably want all of
  your lists to have a standard set of configuration (such as Public
  posting, etc). Gaps could ensure that all lists in your domain have
  the appropriate settings.
- Persisting your group categorization settings back to the Group (as
  part of its description tag).
- Permissioning based off Google settings. Rather than use our custom
  visibility scheme, we could use the group's settings determine
  whether it's considered visible.
- More flexible filter generation, or better story for clearing
  filters.
- Displaying your private lists.
- Fully AJAX-ify the UI. As you can tell, there's still a lot of
  low-hanging fruit on the UI.

# Contributors

- Amber Feng
- Andreas Fuchs
- Brian Krausz
- Carl Jackson
- Evan Broder
- Greg Brockman
