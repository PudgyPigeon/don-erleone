#!/usr/bin/env -S just --justfile

# Variables
system      := `nix eval --raw --impure --expr 'builtins.currentSystem'`
app_name    := "don-erleone" # The package/image name
release_name:= "don_erleone" # The Erlang/OTP release name
cookie      := "don_erleone_cookie"
config      := "config/sys.config"

# Aliases
alias b := build
alias s := dev
alias f := fmt
alias t := test

# Default: List recipes
default:
    @just --list

# --- development ---

[group: 'dev']
dev:
    rebar3 shell --sname {{ release_name }} --setcookie {{ cookie }} --config {{ config }}

[group: 'dev']
reload:
    direnv reload

# --- build & release ---

[group: 'build']
build:
    rebar3 compile

[group: 'build']
release:
    rebar3 as prod release

[group: 'build']
run:
    _build/prod/rel/{{ release_name }}/bin/{{ release_name }} foreground

[group: 'build']
start:
    _build/prod/rel/{{ release_name }}/bin/{{ release_name }} start

# --- test & check ---
[group: 'test']
test:
    # rebar3 do eunit, ct --verbose, cover
    rebar3 eunit

[group: 'check']
fmt:
    rebar3 format

[group: 'check']
ci: fmt
    rebar3 lint
    rebar3 dialyzer

# --- profile ---

[group: 'profile']
observer:
    rebar3 shell --sname {{ release_name }}_obs --eval "observer:start()."

# --- nix ---

[group: 'nix']
nix-build:
    nix build .#default

[group: 'nix']
load-image:
    nix run .#load-image

# --- hygiene ---

[group: 'misc']
clean:
    rebar3 clean
    rm -rf _build result

[group: 'misc']
gc:
    nix-collect-garbage -d