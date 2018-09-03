
const std = @import("std");
const net = @cImport( @cInclude("netinet/in.h") );
const socket = @cImport( @cInclude("sys/socket.h") );
const cio = @cImport( @cInclude("stdio.h") );
const netdb = @cImport( @cInclude("netdb.h") );

const assert = std.debug.assert;
const warn = std.debug.warn;

const irc_port = 6667;
const addr = c"address.of.irc.server"; // c string for gethostbyname() libc call
const channel = "#channel_name";

const nick = "zig_bot";
const real = nick;
const user = nick;

const recv_buf_len = 1024;
var recv_buf: [recv_buf_len]u8 = undefined;

fn strchr(str: []const u8, char: u8) ?usize {
    for (str) |c, i| {
        if (c == char) {
            return i;
        }
    }
    return null;
}

test "strings contain characters" {
    assert(strchr("foobar", 'f').? == 0);
    assert(strchr("foobar", 'o').? == 1);
    assert(strchr("foobar", 'b').? == 3);
    assert(strchr("foobar", 'a').? == 4);
    assert(strchr("foobar", 'x') == null);
}

fn streq(s: []const u8, t: []const u8) bool {
    if (s.len != t.len) {
        return false;
    }

    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != t[i]) {
            return false;
        }
    }

    return true;
}

test "strings are equal to each other" {
    assert(streq("foo bar", "foo bar"));
    assert(streq("", ""));
    assert(! streq("foo", "foobar"));
    assert(! streq("foo", "bar"));
}

fn strstr(str: []const u8, s: []const u8) ?usize {
    if (s.len == 0) {
        return 0;
    }
    outer: for (str) |c, i| {
        if (i + s.len > str.len) {
            break;
        }
        for (s) |sc, si| {
            if (sc != str[i + si]) {
                continue :outer;
            }
        }
        return i;
    }
    return null;
}

test "strings contain other strings" {
    assert(strstr("foobar", "foo").? == 0);
    assert(strstr("foobar", "bar").? == 3);
    assert(strstr("foobar", "foox") == null);
    assert(strstr("foobar", "xfoo") == null);
}

fn parse_nick(line: []const u8) ?[]const u8 {
    if (line[0] == ':') {
        var spce = strchr(line, ' ') orelse return null;
        var excl = strchr(line, '!') orelse return null;

        if (spce < excl) {
            return null;
        }

        var nick_end: usize = excl;
        return line[1..nick_end];
    }
    return null;
}

test "parse nickname" {
    const line = ":tyler!testtesttest foo bar :trail\r\n";
    assert(streq(parse_nick(line).?, "tyler"));

    const line2 = "foo bar :trail\r\n";
    assert(parse_nick(line2) == null);
}

fn parse_command(line: []const u8) ?[]const u8 {
    var cmd_start: usize = 0;
    var cmd_end: usize = 0;

    if (line[0] == ':') {
        cmd_start = strchr(line, ' ') orelse unreachable;
        cmd_start += 1;
        cmd_end = strchr(line[cmd_start..], ' ') orelse strchr(line[cmd_start..], '\r') orelse unreachable;
        cmd_end += cmd_start;
    } else {
        cmd_end = strchr(line, ' ') orelse strchr(line, '\r') orelse unreachable;
    }
    return line[cmd_start..cmd_end];
}

test "parse command" {
    const line = ":tyler!testtesttest foo bar :trail\r\n";
    assert(streq(parse_command(line).?, "foo"));

    const line2 = "foo bar :trail\r\n";
    assert(streq(parse_command(line2).?, "foo"));
}

const CError = error.CError;

fn perror(msg: []const u8) error {
    cio.perror(msg.ptr);
    return error.CError;
}

fn irc_send(sock: i32, value: []const u8) void {
    // for loop on var args kills compiler
    // for (args) |arg| {
    //     warn("{}", arg);
    //     socket.send(sock, arg, arg.len, 0);
    // }
    // var i: usize = 0;
    // while (i < args.len) : (i += 1) {
    //     warn("{}", args[i]);
    //     _ = socket.send(sock, args[i], args[i].len, 0);
    // }
    // inline for (args) |arg| {
    //     warn("{}", arg);
    //     socket.send(sock, arg, arg.len, 0);
    // }
    
    warn("<< {}\n", value);
    _ = socket.send(sock, value.ptr, value.len, 0);
    _ = socket.send(sock, "\r\n", 2, 0);
}


pub fn main() error!void {
    var stdout = try std.io.getStdOut();

    try stdout.write("Test\n");

    const buf_index: usize = 0;

    const host: ?*netdb.hostent = @ptrCast(?*netdb.hostent, netdb.gethostbyname(addr))
        orelse return perror("getaddr");
    const sock: i32 = socket.socket(socket.AF_INET, @enumToInt(socket.SOCK_STREAM), 0);
    if (sock == -1) {
        return perror("sock");
    }

    var remote = net.sockaddr_in{
        .sin_family = socket.AF_INET,
        .sin_port = net.htons(irc_port),
        .sin_addr = undefined,
        .sin_zero = [8]u8{0, 0, 0, 0, 0, 0, 0, 0},
    };
    
    // @ptrCast(*net.in_addr, @alignCast(4, host.?.h_addr_list.?[0].?)).*,

    @memcpy(
        @ptrCast([*]u8, &remote.sin_addr),
        host.?.h_addr_list.?[0].?,
        @sizeOf(@typeOf(remote.sin_addr))
    );

    var conn_result = socket.connect(
        sock,
        @ptrCast([*]const socket.sockaddr, &remote),
        @sizeOf(@typeOf(remote))
    );
    if (conn_result == -1) {
        return perror("connect");
    }

    irc_send(sock, "USER " ++ nick ++ " 0 * :" ++ nick);
    irc_send(sock, "NICK " ++ nick);
    irc_send(sock, "JOIN " ++ channel);

    var buffer_index: usize = 0;

    while (true) {
        // main loop

        var len: isize = 0;
        warn("buffer_index: {}\n", buffer_index);
        len = socket.recv(sock, @ptrCast(?*c_void, &recv_buf[buffer_index]), recv_buf_len - buffer_index, 0);

        // is there a better way to do this?
        var buf_view: []u8 = undefined;
        buf_view.ptr = @ptrCast([*]u8, &recv_buf);
        buf_view.len = @intCast(usize, len) + buffer_index;

        var one_line_end = strchr(recv_buf, '\n');

        while (one_line_end != null) {
            warn("buf view at {} - {}\n", 
                @ptrToInt(buf_view.ptr) - @ptrToInt(&recv_buf),
                @ptrToInt(buf_view.ptr) - @ptrToInt(&recv_buf) + buf_view.len
            );
            warn("buf_view len: {}\n", buf_view.len);
            warn("recv_buf: {x}\n", recv_buf);
            warn("buf_view: {x}\n", buf_view);
            warn("one_line_end: {}\n", one_line_end.?);
            var line = buf_view[0..one_line_end.?-1];
            warn(">> {}\n", line);

            var line_nick = parse_nick(line);
            var line_command = parse_command(line);
            warn(" nick: {}\n", line_nick);
            warn(" command: {}\n", line_command);

            if (streq(line_command.?, "PING")) {
                line[1] = 'O'; // @fragile
                irc_send(sock, line);
            }

            if (streq(line_command.?, "MODE")) {
                irc_send(sock, "PRIVMSG NickServ :IDENTIFY your_password");
                irc_send(sock, "JOIN " ++ channel);
            }

            if (strstr(line, "~test")) |_| {
                irc_send(sock, "PRIVMSG " ++ channel ++ " :ayy test");
            }
            
            // var zero_used: usize = 0;
            // while (buf_view[zero_used] != '\n') : (zero_used += 1) {
            //     buf_view[zero_used] = 0;
            // }
            // buf_view[zero_used] = 0;

            buf_view = buf_view[one_line_end.?+1 ..];
            one_line_end = strchr(buf_view, '\n');
        }
        // warn("recv_buf: 0x{x}\n", @ptrToInt(&recv_buf));
        // warn("buf_view: 0x{x}\n", @ptrToInt(buf_view.ptr));
        // warn("moving {}\n", recv_buf_len - (@ptrToInt(buf_view.ptr) - @ptrToInt(&recv_buf)));
        // @memset(
        //     @ptrCast([*]u8, &recv_buf) + buf_view.len,
        //     0,
        //     recv_buf_len - buf_view.len
        // );
        if (buf_view.len != 0) {
            @memcpy(
                &recv_buf,
                buf_view.ptr,
                buf_view.len,
            );
            // var i: usize = buf_view.len;
            // while (i<recv_buf_len) : (i += 1) {
            //     recv_buf[i] = 0;
            // }
            buffer_index = buf_view.len;
        } else {
            buffer_index = 0;
        }
    }
}

