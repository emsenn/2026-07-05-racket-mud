# Racket-MUD User Guide

Thank you for your interest in using something powered by the Racket-MUD engine! This guide is an introduction to the basic concepts of the engine: the features that are independent of any library your server is running. (Don't worry: jargon like engine, library, and server will all be explicitly defined.)

## MUD Concepts

MUD stands for "multi-user dimension," and is a term used to describe a class of online communities. Most MUDs are games, and many MUDs are role-playing games.

I'm not entirely sure how old MUDs are. Older than the Web, but not as old as the Internet. They aren't the first online game we had, but they're one of the first that used a computer to handle real-time interactions between multiple players and a virtual world.

### Servers and Clients

MUDs exist as a server, and you, the user, connect to them as a client, through an interface.

The server lives on some computer out there on the Internet, and you use a client on your computer to connect to it: log in, enter commands, and receive responses.

Because the commands and responses are text, servers running on Racket-MUD don't require a specific client. There are also a few dedicated MUD clients that offer more features. Point is, you don't need to download a bunch of stuff onto your computer to play a MUD - you can use what's already on your computer.

Say I'm running a game server called The Okaga, running on Racket-MUD at @tt{okaga.emsenn.net}, on port @tt{4242} - actually a small computer sitting on a shelf in my home. That's the server.

You, using a Windows laptop, can open your command line and type @tt{telnet okaga.emsenn.net 4242}. That's your client, and when you connect, you'll be interfacing with the MUD through its MUDSocket service.

### Events and Services

A running Racket-MUD server is always tick-tocking: it calls a set of routine procedures, over and over again, until told to stop by an administrator. A tick is the basic unit of game time: each tick, every scheduled event is triggered, and every service is told to tick.

Events are procedures which work with data internal to the engine, and services are collections of procedures which represent either continously-active things like weather systems, or interfaces like the MUDSocket or web interfaces.

Events are scheduled, meaning stored in a list until the next tick, and then called, rather than being called directly. This helps keep time linear within the engine.

Say you're connected to the Okaga with telnet, and it's tick number 2,047,183 since the engine was started. You're standing in the corridor outside a mess hall, and you submit the command to enter the mess: "go mess"

On tick ...184, after triggering all scheduled events, the engine ticks every service, including the MUDSocket service through which you're connected. The MUDSocket sees that you've submitted a command, and schedules an event to parse it.

On tick 185, the parse event is called, being provided with the in-engine thing representing you, and your command. It does some work to find the appropriate command parser, and then parses the command, scheduling its request.

So on tick 186, the go event is called, being provided with you and your desired destination. The move procedure determines if it's a valid destination, and since it is, it modifies the things representing you, the corridor, and the mess hall to properly track your location, and schedules events like showing "Aleph enters the mess hall," to everyone standing in the mess hall.

### Things and Qualities

I mentioned "things" a few times in the previous section, and unfortunately, that's because it's yet another bit of jargon.

Things are in-engine, well, things. Depending on what optional libraries the engine you're connecting to might be running, things might be everything from a sword to a whale to an office in a skyscraper.

Things have qualities. The qualities a thing has - and the value of those qualities - determine the thing's abilities and what can be done with it.

For example, on server running The Okaga, there are quite a few types of things: two of which are rooms and people. Rooms have a quality, exits, that people don't have, while people have a hitpoints quality that rooms don't have. Both types of things have inventory qualities, though.

### Engines and Libraries

In the previous section I mentioned that the server running The Okaga is using a library. Racket-MUD is intended to be a very basic game engine on its own, so is designed with the intention that additional "MUD libraries" (or "mudlibs") be run on the server to add game or utility features.

At the moment, Racket-MUD is too early in its development to actually have libraries, so I can't provide a realistic-sounding example for this one.

### Overview

So, a MUD server running on the Racket-MUD engine will probably use several MUD libraries to provide a variety of services and events which provide the game features.

The clients interface with the engine through running services, like the one providing an interface through the telnet protocol. Other services maintain game features like weather or NPC movement.

Client interaction and services schedule events, which are procedures affecting things and their qualities, occuring over a continous series of ticks. This moves "time" forward within the engine.

## Getting Started

Now that I've explained most of the technical terms I'll be using, I can hopefully explain how to get started using a server running Racket-MUD without having to interrupt myself.

The first thing you'll need to do as a new user is decide how you want to connect to the MUD: what client do you want to use. Next, you'll actually log in, meaning create a new user account. Finally, you'll be able to input commands to interact with server.

### Connecting

this section isn't really fleshed out yet.

Telnet, MUSHClient, tinyfugue, emacs-mud.

Explanation of MUDSocket service: mccp compression, mxp.

### Logging In

When you first connect to a Racket-MUD, you'll be shown some text, ultimately asking you to enter your user-name - or the user-name you want.

Once you type the name you want, hit enter, and your client will submit the command to the server. It'll do some parsing, and spit back a request: either taking you through logging in or account creation, depending on if your submission was an extant user-name.

### Inputting Commands

Inputting commands is simple: type what you want and hit enter.

The trick is in understanding what syntax the engine expects for various commands. You can input @tt{help --domain=commands -s <command>} to ask what the syntax is for any given @tt{command}, but you'll need to understand the style conventions of the response:

In the above command, 'help' is the command, and '--domain=commands -s <command>' are the parameters. Parameters preceded by a - are "keyword parameters" while those without (typically put at the end of the command) are called "arguments."

Keyword parameters come in two types: those with a value, which start with -- like "--domain=commands", and those without, like -s. Those without a value are called "boolean parameters," because they take a keyword, in this case "s" for "syntax" and toggle it from @bold{false} to @bold{true}.

When displaying syntactical help, parameters shown inside <> are required and should be replaced by appropriate text. Parameters shown inside [] are optional. Parameters separated by | are choices. Don't include the brackets when inputting your command!

Here's what gets shown when you query the 'help' command's syntax:

@tt{help [--domain=commands|concepts|events|services] [-H|s] [term]}

This tells us the help command takes the optional keyword parameter 'domain', set to one of commands, concepts, events, or services. We can also pass it either the H or s boolean parameter, and a term. 

So to describe the command above, you would say it is the help command submitted with the s boolean keyword parameter, the domain keyword parameter set to commands, and 

## Commands

This section is a brief explainer of the basic commands provided to you by the Racket-MUD engine. This probably isn't comprehensive: depending on what libraries the MUD server you're connecting to is running, you might have access to many many more commands.

### `account` Command

The account command provides an interface with the User service. A user is the record about a given account; while you might be a MUDSocket or Web client, you'll always be a "user."

### `alias` Command

Thie 'alias' command is how you can set up alternative ways to call commands. For example, you might set up an alias of @tt{talker --channel=one history} to @tt{hone}.

### `commands` Command

The 'commands' command is how you can see just what commands you have available. It's syntax is simple: just 'commands'.

### `finger` Command

The 'finger' command is how you can see information about a user account.

### `help` Command

The 'help' command is how you can request helpful information from the client, about your commands, engine events and services, and other concepts.

todo: syntax explainer.

## Account Management
### Your Profile
Once you create a user account, other people can find out information about it by using the 'finger' command with your user-name. You can customize what information is displayed here with the 'account' command.

## The Talker
The Talker service handles in-engine chatting: communication between players occuring on pre-defined channels.