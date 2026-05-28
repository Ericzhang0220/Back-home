# back_home

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


Moderation Note: users can only make 100 comments/day



Private vs Public Profile Differences:
- public profile avatar cannot be editted
- happiness index card section visibility dependent on owner settings (UI to set visibility of self is needed here)
- reading comfort, audio settings, or anything below private only
- public variant has social buttons below the three stat pills
- stat pills visibility for each should also be configurable by the user
- all visibility setting are not visible in the public variant of the profile page
- Posts and Likes Buttons also below the social buttons
    - Posts button shows a timeline of the user's posts
    - Likes button shows a timeline of what that user followed
- UPDATE: move all settings into a subscreen that can be reached by a settings button on the top right corner of the profile screen

Chat Screen:
- users can message one another only if mutually following
- if not, then max 1 sentence (probably character limit)
- 



Checking for wireless devices...

[1]: Eric的iPhone (00008120-000661A62E7B601E)
[2]: iPhone 16e (3200CDA0-8D1B-4F00-90F5-5D4EE5F203EE)
[3]: macOS (macos)
[4]: Chrome (chrome)
Please choose one (or "q" to quit): 1
Launching lib/main.dart on Eric的iPhone in debug mode...
Automatically signing iOS for device deployment using specified development
team in Xcode project: N3PX95D3HF
Running Xcode build...                                                  
Xcode build done.                                           26.7s
Process 58731 stopped
* thread #1, stop reason = signal SIGKILL
    frame #0: 0x0000000196a8578c dyld`lldb_image_notifier
dyld`lldb_image_notifier:
->  0x196a8578c <+0>: ret    

dyld`close:
    0x196a85790 <+0>: mov    x16, #0x6                 ; =6 
    0x196a85794 <+4>: svc    #0x80
    0x196a85798 <+8>: b.lo   0x196a857b8               ; <+40>
Target 0: (Runner) stopped.
The Dart VM Service was not discovered after 60 seconds. This is taking much
longer than expected...
Installing and launching...  