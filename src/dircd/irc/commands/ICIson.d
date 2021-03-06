module dircd.irc.commands.ICIson;

import dircd.irc.commands.ICommand;
import dircd.irc.LineType;
import dircd.irc.User;

public class ICIson : ICommand {

    public string getName() {
        return "ISON";
    }

    public void run(User u, Captures!(string, ulong) line) {
        auto nickList = line["params"];
        if (nickList.strip() == "") {
            u.sendLine(u.getIRC().generateLine(u, LineType.ErrNeedMoreParams, "ISON :Not enough parameters"));
            return;
        }
        string reply = ":";
        foreach (string nick; nickList.split(",")) {
            nick = nick.strip(); // bad clients
            if (nick == "") continue; // invalid nick
            foreach (User user; u.getIRC().getUsers()) if (user.getNick() == nick) reply ~= user.getNick() ~ ",";
        }
        if (reply.split(",").length > 1) reply = reply[0..$-1]; // cut off last ","
        u.sendLine(u.getIRC().generateLine(u, LineType.RplIsOn, reply));
    }

}
