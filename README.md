# Vosh

Vosh, a contraction between Vision and Macintosh, is my attempt at creating a screen-reader  for MacOS from scratch. This project draws inspiration, though not code, from a similar open-source project for Windows called NVDA, and is motivated by Apple's neglect of VoiceOver on the Mac compared to its mobile counterpart. While this is very experimental code with lots of missing features and known bugs, I just wanted to get something out there in order to follow through with a promise that I made of making it free and open-source.

This project depends on very poorly documented APIs from Apple, and as such I cannot guarantee anything about its future, but will continue to work on it for as long as I can keep coming up with ways to work around the MacOS consumer-side accessibility API's quirks. Will it ever be able to compete with VoiceOver? I'm not sure, but my motivation is also fueled by the challenge to find solutions for hard problems even if what I do ends up not being very useful.

At the moment you can already navigate apps that have windows and can become active including Safari, however there are a number of major issues to solve before I can even consider this code ready for testing. If you wish to help, check out the the project's issues page, which I will be updating with new issues as I become aware of them.

## Building

Before you begin, I strongly recommend you to try this on a virtual machine, because even if you trust me (which you shouldn't) this software might have bugs and security issues and the instructions provided here will require granting Terminal and any application run from it the ability control your computer, unless you remember to revoke those permissions later.

Vosh is distributed as a Swift package, so in order to build it you will need at least Xcode's command-line tools, however don't worry much about it since MacOS will prompt you and guide you through their installation process once you start entering the commands below. Xcode is also supported, and you will likely want to use it if you decide to tinker with the code, but the advantage of the command-line is that it makes it much easier to provide instructions on the Internet. If you don't feel comfortable following these instructions then you are not yet the target audience for this project.

Start off by downloading this git repository by typing:

    git clone https://github.com/Choominator/Vosh.git

If everything goes well you should now have a new directory named Vosh in your current working directory, so type the following to get inside:

    cd Vosh

And then run a debug build by typing:

    swift run

Doing this will result in a prompt asking you to grant accessibility permissions to Terminal, which will allow any applications started by it (Vosh in this case) to control your computer. This is intentional, because without these permissions Vosh cannot tap into the input event stream or communicate with accessible applications through the accessibility consumer interface. Since Vosh exits immediately when it lacks permissions, you'll have to execute the above command once more to start it normally after granting the requested permissions.

If you just want to mess around with Vosh then the above is all you need to do in order to get it running. However, if you wish to tinker with the code in Xcode, instead of building the code using the command above, there are a few things that need to be done.

To open the project in Xcode, type:

    xed .

This project does not ship with any Xcode schemes, which is intentional as there's currently no portable way to code-sign it. As a result you'll need to take some extra steps if you wish to take advantage of Xcode to compile, debug, and run the project.

First you'll need to create the default scheme, which Xcode should prompt you to do the first time you open this package in it, but if it doesn't you can do so manually by going to Product -> Scheme -> Manage Schemes... and clicking on the autocreate Schemes Now button.

At this point you can already build Vosh, but there's a problem, which is that the final executable will have an ad-hoc code signature whose authenticity cannot be verified by Gatekeeper, and as such you will need to revoke and grant the accessibility permissions after every change to the code, which is not very comfortable. To work around this problem I believe that you need to be enrolled in the paid Apple Developer Program, and here I say that I believe because I'm on a paid membership and cannot check whether the instructions below also work with the free membership.

Before setting up the default scheme to code-sign you will need two obtain two pieces of information: the identity of your development certificate in Keychain and the location of Xcode's DerivedData directory in your home directory.

To obtain the identity of your development certificate, type the following:

    security find-identity -p basic -v

Which should output something like:

      1) XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX "Apple Development: John Doe (XXXXXXXXXX)"
         1 valid identities found

Where the text we're interested in is `Apple Development: John Doe (XXXXXXXXXX)`.

By default the location of Xcode's DerivedData directory is at `~/Library/Developer/Xcode/DerivedData`, however this can be changed in Xcode's preferences, so check there for the right location, or use the following command to do so from the command-line:

    defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation

Finally, to automatically code-sign the executable you will need to edit the default scheme by going to Product -> Scheme -> Edit Schemes..., expand the Build row in the Scheme Type table, select Post-actions, and add a new Run Script action with the following code, replacing `~/Library/Developer/Xcode/DerivedData` with the path to the DerivedData directory for your user, as well as `Apple Development: John Doe (XXXXXXXXXX)` with the identity of your code-signing development certificate, and leaving everything else intact:

    find ~/Library/Developer/Xcode/DerivedData -name Vosh -type f -perm -700 -mtime -1 -exec codesign -s 'Apple Development: John Doe (XXXXXXXXXX)' '{}' ';'

After making this change, go to Product -> Build to build the project, and then read the topmost entry of Report Navigator to verify that the scheme did not produce any errors.

Once everything is set up correctly you will be free to make changes to the code without having to grant accessibility privileges to Vosh all the time.

## Usage

Vosh uses CapsLock as its special key, referred from here on as the Vosh key, and as such modifies its behavior so that you need to double-press it to turn CapsLock on or off.

The following is the list of key combinations currently supported by Vosh:

* Vosh+Tab - Read the focused element.
* Vosh+Left - Focus the previous element;
* Vosh+Right - Focus the next element;
* Vosh+Down - Focus the first child of the focused element;
* Vosh+Up - Focus the parent of the focused element;
* Vosh+Slash - Dump the system-wide element to a property list file;
* Vosh+Period - Dump all elements of the active application to a property list file;
* Vosh+Comma - Dump the focused element and all its children to a property list file;
* Control - Interrupt speech.

At present, the only user interfaces presented by Vosh are the save panel where you can choose the location of the element dump property list files and a menu extras that can be used to exit Vosh, though neither of these interfaces work with Vosh itself, and even VoiceOver has very poor support for graphical user interfaces in modal windows, so expect some accessibility issues using them.

The element dumping commands are used to provide information that can be attached to issues for me to analyze on bug reports. These commands dump the hierarchy of an accessible application or a focused element within an accessible application complete with all of their respective attribute values, meaning that the dump files might contain personal or confidential information, which is yet another reason to only run this project on a virtual machine.
