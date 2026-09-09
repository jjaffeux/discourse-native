import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Isolated review entrypoint: local data only, mounting real app controls.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const ButtonReview());
}

class ButtonReview extends StatefulWidget {
  const ButtonReview({super.key});
  @override
  State<ButtonReview> createState() => _ButtonReviewState();
}

class _ButtonReviewState extends State<ButtonReview> {
  StyleguideTheme theme = StyleguideTheme.light;
  bool rtl = false;
  bool large = false;
  String message = 'No application action yet';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.resolve(AppTheme.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(large ? 2 : 1),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DButton(
                          label: const Text('Styleguide'),
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const ComponentStyleguidePage(),
                            ),
                          ),
                        ),
                        for (final value in StyleguideTheme.values.where(
                          (v) => v != StyleguideTheme.current,
                        ))
                          DButton(
                            label: Text(value.label),
                            variant: DButtonVariant.outline,
                            onPressed: () => setState(() => theme = value),
                          ),
                        DButton(
                          label: Text(rtl ? 'LTR' : 'RTL'),
                          onPressed: () => setState(() => rtl = !rtl),
                        ),
                        DButton(
                          label: Text(large ? '100%' : '200%'),
                          onPressed: () => setState(() => large = !large),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(message),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'multiple',
                        type: PollType.multiple,
                        min: 1,
                        max: 2,
                        options: [
                          PollOption(id: 'a', html: 'Alpha'),
                          PollOption(id: 'b', html: 'Beta'),
                        ],
                      ),
                      signedIn: true,
                      archived: false,
                      onVote: (_, ids) async {
                        await Future<void>.delayed(const Duration(seconds: 2));
                        if (mounted) {
                          setState(() => message = 'Saved ${ids.join(', ')}');
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'signed-out',
                        options: [PollOption(id: 'a', html: 'Connect to vote')],
                      ),
                      signedIn: false,
                      archived: false,
                      onConnectAccount: () => setState(
                        () => message = 'Local account connection action',
                      ),
                    ),
                    const SizedBox(height: 16),
                    PollCard(
                      poll: const Poll(
                        name: 'web',
                        type: PollType.rankedChoice,
                        options: [
                          PollOption(id: 'a', html: 'Web voting option'),
                        ],
                      ),
                      signedIn: true,
                      archived: false,
                      onVoteOnWeb: () => setState(
                        () => message = 'Local vote-on-web navigation action',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
