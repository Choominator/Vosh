# Vosh

Vosh, a contraction of the words Vision and Macintosh, is my abandoned attempt at creating a screen-reader for MacOS from scratch. This project draws inspiration, though not code, from a similar open-source project for Windows called NVDA, and was motivated by Apple's neglect of VoiceOver on the Mac compared to its mobile counterpart. At the moment you can navigate apps that have windows and can become active including Safari, however there are a number of major issues that need addressing, and I'm no longer that interested in this code so I'll just keep it around for historical purposes.

This project depends on very poorly documented APIs from Apple. While I no longer have time to commit to this, I still intend to keep updating it from time to time with improvements to the safe abstractions to Apple's Carbon-based consumer-side accessibility framework, which is extremely poorly designed and whose implementations fail a lot in terms of memory safety in concurrent environments, including in situations where Carbon itself, as well as other Carbon-based frameworks like CoreAudio, guarantee or make it reasonable to expect thread-safety, so nothing can be left for chance when it comes to multi-threaded code in the context of consumer-side Accessibility on macOS. The current update is on par with Swift 6.2 on macOS 26.

## Building

The following instructions must be executed in Terminal, so if you aren't comfortable with that, you are definitely not the target audience of this project in its current state. Also before you begin, I strongly recommend only trying this on a virtual machine, because even if you trust me (which you shouldn't) this software may have bugs and security issues and the instructions provided here will require granting it the ability control your computer. Vosh is distributed as a Swift package, so in order to build it you will need at least the Swift Package Manager shipped with Xcode. While Xcode's command-line tools also ship with the Swift Package Manager, that distribution in particular had historical problems building Swift packages targeting macOS, so only the Swift Package Manager shipped with Xcode as well as Xcode itself are guaranteed to work properly.

Start off by downloading the [main branch][main-zip], unzipping the code, and opening a Terminal in the project directory.

[main-zip]: https://github.com/FriduxTech/Vosh/archive/main.zip

After performing the above steps, generate and launch a development build of Vosh by typing the following inside its base directory:

    swift run

Doing this will result in a prompt asking you to grant accessibility permissions to Terminal, which will allow any applications started by it (Vosh in this case) to control your computer. This is intentional, because without these permissions Vosh cannot tap into the input event stream or communicate with accessible applications through the accessibility infrastructure. Since Vosh exits immediately when it lacks permissions, you'll have to execute the above command once more to start it normally after granting the requested permissions.

Alternatively, you can also open the package in Xcode by typing the following in its base directory':

    xed .

When Vosh is built and executed directly from Xcode, it is assigned its own set of privileges, which require a code signature to be properly tracked by the Transparency, Consent, and Control feature of macOS commonly known as Gatekeeper. Since the Swift Package Manager is not designed with this in mind, and compiles in a sandboxed environment by default for security reasons, it is not possible to automatically sign the code from a standard Swift package build. However Xcode has the ability to generate and consume its own schemes to be distributed along with Swift packages targeting the Apple ecosystem, so I'm taking advantage of that to automatically look for valid Apple Development certificates on the system, and if exactly one is found, use it to sign the compiled code every time the project is built.

To build the project in Xcode, go to Product -> Build or alternatively press Command+B by default, and then read the topmost entry of Report Navigator to verify that the aforementioned scheme executed successfully, which should be the case even if the aforementioned code-signing conditions are not met. If the code is successfully signed, then you should only need to grant privileges to Vosh once regardless of how much you change the codebase. To run the code, go to Product -> Run or alternatively press Command+R by default.

## Usage

Vosh uses CapsLock as its special key, referred from here on as the Vosh key, and as such modifies its behavior so that you need to double-press it to toggle its status.

The following is the list of key combinations currently supported by Vosh:

* Vosh+Tab - Read the focused element.
* Vosh+Left - Focus the previous element;
* Vosh+Right - Focus the next element;
* Vosh+Down - Focus the first child of the focused element;
* Vosh+Up - Focus the parent of the focused element;
* Vosh+Slash - Dump the system-wide element to a property list file;
* Vosh+Period - Dump all elements of the active application to a property list file;
* Vosh+Comma - Dump the focused element and all its children to a property list file;
* Vosh or Control - Interrupt speech.

The only user interfaces presented by Vosh are its menu in the Menu Extras area of the menu bar as well as save panel where you can choose the location of the element dump property list files, though neither of these interfaces work with Vosh itself, and even VoiceOver has very poor support for graphical user interfaces in modal windows, so expect some accessibility issues using them. The element dumping commands are used to provide information that can be used to analyze the structure of an application's 'accessibility hierarchy, and may contain sensitive information, hence yet another reason to only try this code on a virtual machine.
