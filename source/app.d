

import vibe.d;

import dircd.irc.IRC;

import std.c.stdlib: exit;
import std.getopt: getopt, config;

string hostname = "127.0.0.1";
string password;
ushort port = 6667;

shared static this ( )
{
    auto irc = new IRC(hostname, port, password);
    listenTCP(port, &irc.handleTCP);
}
