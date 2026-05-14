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