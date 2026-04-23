#!/usr/bin/env -S just --justfile

# Variables
system      := `nix eval --raw --impure --expr 'builtins.currentSystem'`
app_name    := "don_erleone"
otp_name    := "don_erleone"
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

[group: 'dev']
dev:
    rebar3 shell --sname {{ otp_name }} --setcookie {{ cookie }} --config {{ config }}

[group: 'dev']
reload:
    direnv reload


[group: 'build']
build:
    rebar3 compile

[group: 'build']
release:
    rebar3 as prod release

[group: 'build']
run:
    _build/prod/rel/{{ otp_name }}/bin/{{ otp_name }} foreground

[group: 'build']
start:
    _build/prod/rel/{{ otp_name }}/bin/{{ otp_name }} start


[group: 'test']
test:
    rebar3 do eunit, ct --verbose, cover

[group: 'check']
fmt:
    erlfmt -w src/*.erl rebar.config
    # rebar3 format

[group: 'check']
ci: fmt
    rebar3 lint
    rebar3 dialyzer


[group: 'profile']
observer:
    rebar3 shell --sname {{ otp_name }}_obs --eval "observer:start()."


[group: 'nix']
nix-build:
    nix build .#default

[group: 'nix']
load-image:
    nix run .#load-image


[group: 'misc']
clean:
    rebar3 clean
    rm -rf _build result

[group: 'misc']
gc:
    nix-collect-garbage -d