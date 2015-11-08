module dircd.irc.IRC;

import vibe.core.net  : TCPConnection;
import vibe.core.core : runTask;

import dircd.irc.Channel;
import dircd.irc.commands._;
import dircd.irc.LineType;
import dircd.irc.User;

import std.algorithm: remove, startsWith;
import std.c.stdlib: exit;
import std.conv: to;
import std.datetime: Clock, SysTime;
import std.regex: regex, Regex, match, rreplace = replace, Captures;
import std.stdio: writeln;
import std.string: toLower, strip;
import std.utf: UTFException, toUTF8;

public class IRC {
    /**
    * This supports &amp;, +, !, and # as channel starters (per IRC RFC - see
    * http://tools.ietf.org/html/rfc1459.html#section-1.3). The only additional restriction on channel names imposed
    * by this server is that there may be no carriage returns or line breaks in the channel name.
    * In this server, RFC is not followed for channel prefix meanings to the fullest extent.
    * &amp;, !, and # are normal channels.
    * + is a no-mode channel (per RFC).
    */
    private Regex!char chanRegex = regex(r"^([&#+!][^\x07, \r\n]{1,50})$", "g");
    private Regex!char lineRegex = regex(r"^(:(?P<prefix>\S+) )?(?P<command>\S+)( (?!:)(?P<params>.+?))?( :(?P<trail>.+)?)?$", "g");
    private string host;
    private string pass;
    private ushort port;

    private SysTime created;

    private CommandHandler ch = new CommandHandler();

    private User[] users;
    private Channel[string] channels;

    public this(string host, ushort port, string pass) {
        created = Clock.currTime;
        addCommands();
        this.host = host, this.port = port, this.pass = pass;
    }

    private void addCommands() {
        ch.addCommand(new ICCap());
        ch.addCommand(new ICIson());
        ch.addCommand(new ICJoin());
        ch.addCommand(new ICMode());
        ch.addCommand(new ICNames());
        ch.addCommand(new ICNick());
        ch.addCommand(new ICNotice());
        ch.addCommand(new ICPart());
        ch.addCommand(new ICPass());
        ch.addCommand(new ICPong());
        ch.addCommand(new ICPrivmsg());
        ch.addCommand(new ICQuit());
        ch.addCommand(new ICTopic());
        ch.addCommand(new ICUser());
        ch.addCommand(new ICWho());
    }

    public SysTime getTimeCreated() {
        return this.created;
    }

    public CommandHandler getCommandHandler() {
        return this.ch;
    }

    public string getHost() {
        return this.host;
    }

    public string getPass() {
        return this.pass;
    }

    public short getPort() {
        return this.port;
    }

    public User[] getUsers() {
        return this.users;
    }

    public User getUser(string name) {
        name = name.strip(); // bad clients are bad
        // do regex check here later
        foreach (User u; users) if (u.getNick() == name) return u;
        return null;
    }

    public Channel[] getChannels() {
        return this.channels.values;
    }

    public Channel getChannel(string name) {
        name = name.strip(); // bad clients are bad
        auto match = name.match(chanRegex);
        if (!match) return null;
        if (name.toLower() in channels) return channels[name.toLower()];
        auto chan = new Channel(this, name);
        channels[name.toLower()] = chan;
        return chan;
    }

    public string generateLine(LineType lt, string params) {
        return ":%s %03d %s".format(getHost(), lt, params);
    }

    public string generateLine(User target, LineType lt, string params) {
        return ":%s %03d %s %s".format(getHost(), lt, target.getNick(), params);
    }

    public bool startsWithChannelPrefix(string s) {
        return s.startsWith("#") || s.startsWith("!") || s.startsWith("+") || s.startsWith("&");
    }

    public Captures!(string, ulong) parseLine(string line) {
        auto match = line.match(lineRegex);
        if (!match) throw new Exception("Not a valid line");
        return match.captures;
    }

    public void removeUser(User u) {
        int index = -1;
        for (int i = 0; i < users.length; i++) {
            if (users[i].getNick() != u.getNick()) continue;
            index = i;
            break;
        }
        if (index == -1) return;
        users = users.remove(index);
    }

    public void removeChannel(Channel c) {
        auto name = c.getName().toLower();
        if (name !in channels) return;
        channels.remove(name);
    }

    public void addUser(User u) {
        users ~= u;
    }

    /** Handle incoming TCP connections. */
    public void handleTCP (TCPConnection conn) {

        auto user = new User(this);
        addUser(user);

        // Start reading in extra fiber
        auto reader = runTask(&startReading, conn, user);//, client_context);

        scope(exit)
        {
            if(conn.connected)
                conn.close();

            if (user.pipe.connected)
                user.pipe.close();

            user.disconnect("Lost connection");

            reader.interrupt();
            reader.join();
        }

        while (conn.connected && reader.running && user.isConnected())
        {
            // send in case something is written into the pipe
            if (user.pipe.waitForData(dur!"seconds"(1)))
                conn.write(user.pipe, user.pipe.leastSize);
        }
    }

    public void startReading(TCPConnection conn, User user) {

        scope(exit)
        {
            if (conn.connected)
                conn.close();

            if (user.pipe.connected)
                user.pipe.close();
        }

        bool bWaitPong;
        string receivedText;
        char[1] buffer;
        Captures!(string, ulong) line;
        while (conn.connected && user.isConnected())
        {
            while ( conn.waitForData(dur!"seconds"(60)) == false )
            {
                if (bWaitPong)
                {
                    // user was inactive for 120 seconds and did not pong back
                    conn.close();
                    writeln("user didn't pong");
                    break;
                }
                else
                {
                    // check if user is still alive after 60 seconds
                    conn.write("PING 127.0.0.1\n");
                    conn.flush();
                    writeln("asking for pong");
                    bWaitPong = true;
                }
            }

            // user seems alive
            bWaitPong = false;

            receivedText = "";
            while(receivedText.length == 0 ? true : receivedText[$-1] != '\n')
            {
                conn.read((cast(ubyte*)&buffer)[0 .. 1]);
                receivedText ~= to!string(buffer[0 .. 1]);
            }

            writeln("RECV %s: %s".format(user.getHostmask(),
                    receivedText.rreplace(regex(r"\r?\n"), "")));

            try {
                line = parseLine(receivedText.rreplace(regex(r"\r?\n"), ""));
            } catch (Exception e) {
                writeln(e);
                continue;
            }
            auto command = line["command"].toUpper();

            if (getPass() !is null && !user.correctPass) {
                if (command != "PASS" && command != "PONG" && command != "CAP") continue;
            }
            if (!user.isRegistered() && (command != "CAP" && command != "PONG" && command != "USER" && command != "NICK")) continue;

            auto ic = getCommandHandler().getCommand(command);
            if (ic is null) {
                user.sendLine(generateLine(user, LineType.ErrUnknownCommand, command ~ " :Unknown command"));
                continue;
            }
            ic.run(user, line);
        }
    }
}
