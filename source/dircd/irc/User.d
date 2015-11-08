module dircd.irc.User;

import core.time: dur;

import dircd.irc.cap.Capability;
import dircd.irc.Channel;
import dircd.irc.IRC;
import dircd.irc.LineType;
import dircd.irc.modes.ChanMode;
import dircd.irc.modes.Mode;
import dircd.irc.modes.UserMode;

import vibe.stream.taskpipe;

import std.algorithm: remove;
import std.conv: to;
import std.datetime: Clock;
import std.regex: regex, rreplace = replace, match;
import std.stdio: writeln;
import std.string: split, toUpper, strip, format, capitalize;
import std.traits: EnumMembers;

public class User {

    private TaskPipe _pipe;
    private IRC irc;

    private Channel[] channels;

    private string nick;
    private string realName;
    private string user;
    private string hostname;

    private UserMode[] modes;
    private Capability[] caps;

    private const long connTime;

    private bool connected;
    private bool welcomeSent;
    public bool correctPass;

    public this(IRC server) {
        this.irc = server;
        this.connTime = Clock.currTime().toUnixTime();
        this.connected = true;
        this.correctPass = false;
    }

    @property TaskPipe pipe ( )
    {
        if (_pipe is null)
        {
            this._pipe = new TaskPipe();
        }
        return _pipe;
    }

    public void sendWelcome() {
        if (welcomeSent) return;
        this.sendLine(this.irc.generateLine(this, LineType.RplWelcome, "Welcome to dIRCd."));
        this.sendLine(this.irc.generateLine(this, LineType.RplYourHost, "Your host is %s, running version %s".format(this.irc.getHost(), "dIRCd[v1.0]")));
        auto created = this.irc.getTimeCreated();
        this.sendLine(this.irc.generateLine(this, LineType.RplCreated, "This server was created %s %d %d at %02d:%02d:%02d".format(to!string(created.month).capitalize(), created.day, created.year, created.hour, created.minute, created.second)));
        string modes = "";
        foreach (member; EnumMembers!UserMode) modes ~= member;
        modes ~= " ";
        foreach (member; EnumMembers!ChanMode) modes ~= member;
        this.sendLine(this.irc.generateLine(this, LineType.RplMyInfo, "%s %s %s".format(this.irc.getHost(), "dIRCd[v1.0]", modes)));
        this.sendLine(this.irc.generateLine(this, LineType.RplMotdStart, ""));
        this.sendLine(this.irc.generateLine(this, LineType.RplMotdEnd, ""));
        welcomeSent = true;
    }

    public bool isRegistered() {
        return nick !is null && user !is null;
    }

    public Capability[] getCapabilities() {
        return this.caps;
    }

    public void setCapabilities(Capability[] caps) {
        this.caps = caps;
    }

    public UserMode[] getModes() {
        return this.modes;
    }

    public void setModes(UserMode[] modes) {
        this.modes = modes;
    }

    public void sendModes() {
        sendModes(this);
    }

    public void sendModes(User u) {
        string toSend = "+";
        foreach (UserMode um; this.getModes()) toSend ~= um;
        u.sendHostLine("MODE %s %s".format(this.getNick(), toSend));
    }

    public bool isConnected() {
        return this.connected;
    }

    public long getConnectionTime() {
        return this.connTime;
    }

    public IRC getIRC() {
        return irc;
    }

    public string getNick() {
        return this.nick;
    }

    public void setNick(string newNick) {
        auto line = ":%s NICK :%s".format(this.getHostmask(), newNick);
        User[string] sent;
        this.sendLine(line);
        foreach (Channel c; this.getChannels()) {
            if (c.hasMode(ChanMode.Anonymous)) continue; // don't tell people in anon channels
            foreach (User u; c.getUsers()) {
                if (u.getNick() in sent || u.getNick() == this.getNick()) continue; // don't need to notify twice
                u.sendLine(line);
                sent[u.getNick()] = u;
            }
        }
        this.nick = newNick;
    }

    public string getRealName() {
        return this.realName;
    }

    public void setRealName(string realName) {
        this.realName = realName;
    }

    public string getHostmask() {
        return "%s!%s@%s".format(getNick(), getUser(), getHostname());
    }

    public string getUser() {
        return this.user;
    }

    public string getHostname() {
        return this.hostname;
    }

    public void setHostname(string hostname) {
        this.hostname = hostname;
    }

    public void setUser(string user) {
        if (user.length > 9) user = user[0..9];
        this.user = user;
    }

    public Channel[] getChannels() {
        return this.channels;
    }

    public void addChannel(Channel c) {
        this.channels ~= c;
    }

    public void removeChannel(Channel c) {
        int index = -1;
        for (int i = 0; i < channels.length; i++) {
            if (channels[i].getName() != c.getName()) continue;
            index = i;
            break;
        }
        if (index == -1) return;
        this.channels = channels.remove(index);
    }

    public void sendLine(string line) {
        writeln("SENT %s: %s".format(this.getHostmask, line));
        ubyte[] b = cast(ubyte[])(line ~ "\r\n");
        _pipe.write(b);
    }

    public void sendHostLine(string line) {
        sendLine(":%s %s".format(this.getIRC().getHost(), line));
    }

    public void sendMessage(User who, string message) {
        sendLine(":%s PRIVMSG %s :%s".format(who.getHostmask(), this.getNick(), message));
    }

    public void sendNotice(User who, string message) {
        sendLine(":%s NOTICE %s :%s".format(who.getHostmask, this.getNick, message));
    }

    public void disconnect(string reason) {
        if (!connected) return;
        foreach (Channel c; this.getChannels()) {
            c.quitUser(this, reason);
        }
        this.getIRC().removeUser(this);
        this.connected = false;
    }
}
