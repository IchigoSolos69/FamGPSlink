import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'family_controller.dart';
import 'models.dart';

const mapStyle = 'https://tiles.openfreemap.org/styles/bright';

String readableError(Object exception) {
  if (exception is PlatformException) {
    return exception.message ?? 'Check location permissions and try again.';
  }
  if (exception is FirebaseAuthException) {
    return exception.code == 'network-request-failed'
        ? 'Check your connection and try again.'
        : 'Check your email and password, or use password recovery.';
  }
  if (exception is FirebaseException) {
    if (exception.code == 'permission-denied') {
      return 'The family server rejected this change (permission-denied). Retry the connection; if it continues, ask the owner to check your device approval.';
    }
    return 'The family server could not save this change (${exception.code}). Check your connection and try again.';
  }
  if (exception is StateError) return exception.message.toString();
  return 'Could not save this change. Check your connection and try again.';
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(readableError(exception))));
    }
    return false;
  }
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(),
              SizedBox(height: 24),
              Text(
                'Your family, connected',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                'This build is not connected to your family yet. Ask the family owner for a configured build.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String startupErrorCode(Object error) {
  final code = error is FirebaseException
      ? '${error.plugin}/${error.code}'
      : error is PlatformException
      ? error.code
      : 'startup-failed';
  final safeCode = code.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '');
  return safeCode.length <= 80 ? safeCode : safeCode.substring(0, 80);
}

String startupErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return 'This phone could not reach sign-in. Check Wi-Fi or mobile data and try again.';
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Sign-in is temporarily limited. Wait a few minutes and try again.';
      case 'operation-not-allowed':
        return 'Member sign-in is unavailable. Ask the family owner to check sign-in settings.';
      case 'invalid-api-key':
      case 'app-not-authorized':
        return 'Sign-in could not verify this app. Ask the family owner for the latest build.';
      default:
        return 'This phone could not complete sign-in. Try again or share the error code with the family owner.';
    }
  }
  return 'This phone could not open the family connection or saved profile. Try again or share the error code with the family owner.';
}

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
  });
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(),
                const SizedBox(height: 24),
                Text(
                  'Couldn’t open FamGPSlink',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(startupErrorMessage(error), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                SelectableText(
                  'Error code: ${startupErrorCode(error)}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 80,
    height: 80,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(25),
    ),
    child: const Icon(Icons.home_work_rounded, size: 44, color: Colors.white),
  );
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final name = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark()),
                  const SizedBox(height: 24),
                  Text(
                    'A little closer.\nWherever you are.',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Share your latest location with your family. You choose when sharing is on.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (family.error != null) ...[
                    Text(
                      family.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: () => perform(context, family.retry),
                      child: const Text('Retry connection'),
                    ),
                  ],
                  if (family.request != null) ...[
                    Text(
                      'Hi, ${family.request!.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Give this pairing code to the family owner. They can add you or reconnect your existing profile.',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        family.request!.code,
                        style: const TextStyle(
                          fontSize: 30,
                          letterSpacing: 5,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: family.request!.code),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy pairing code'),
                    ),
                    const Text(
                      'Waiting for owner approval…',
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    TextField(
                      controller: name,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              await perform(
                                context,
                                () => family.createRequest(name.text),
                              );
                              if (mounted) setState(() => busy = false);
                            },
                      child: Text(busy ? 'Connecting…' : 'Join my family'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OwnerLoginPage(controller: family),
                      ),
                    ),
                    child: const Text('Family owner sign-in'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your profile is remembered on this phone. Reinstalling or changing phones needs owner approval.',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerLoginPage extends StatefulWidget {
  const OwnerLoginPage({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<OwnerLoginPage> createState() => _OwnerLoginPageState();
}

class _OwnerLoginPageState extends State<OwnerLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owner sign-in')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Use the owner account configured for your family.'),
        const SizedBox(height: 24),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  final saved = await perform(
                    context,
                    () => widget.controller.signInOwner(
                      email.text,
                      password.text,
                    ),
                  );
                  if (context.mounted) {
                    setState(() => busy = false);
                    if (saved) Navigator.of(context).pop();
                  }
                },
          child: Text(busy ? 'Signing in…' : 'Sign in'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => perform(
                  context,
                  () => widget.controller.resetOwnerPassword(email.text),
                  success: 'If this email has an account, password recovery instructions will be sent.',
                ),
          child: const Text('Forgot password?'),
        ),
      ],
    ),
  );
}

class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> with WidgetsBindingObserver {
  int page = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.setMapVisible(true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => widget.controller
      .setMapVisible(page == 0 && state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setMapVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'FamGPSlink',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Chip(
            avatar: Icon(
              widget.controller.connected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 16,
            ),
            label: Text(widget.controller.connected ? 'Connected' : 'Offline'),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        if (widget.controller.error != null)
          MaterialBanner(
            content: Text(widget.controller.error!),
            actions: [
              TextButton(
                onPressed: () => perform(context, widget.controller.retry),
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: page == 0
              ? FamilyMap(controller: widget.controller)
              : SettingsPage(controller: widget.controller),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (index) {
        setState(() => page = index);
        widget.controller.setMapVisible(index == 0);
      },
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: widget.controller.isPrivateConnection
              ? 'Private map'
              : 'Family map',
        ),
        const NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
      ],
    ),
  );
}

class FamilyMap extends StatefulWidget {
  const FamilyMap({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<FamilyMap> createState() => _FamilyMapState();
}

class _FamilyMapState extends State<FamilyMap> {
  MapLibreMapController? map;
  bool styleReady = false;
  bool drawing = false;
  bool drawAgain = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(update);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        unawaited(draw());
      }
    });
  }

  void update() {
    if (mounted) {
      setState(() {});
      unawaited(draw());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.controller.removeListener(update);
    super.dispose();
  }

  Future<void> draw() async {
    if (!mounted || !styleReady || map == null) return;
    if (drawing) {
      drawAgain = true;
      return;
    }
    drawing = true;
    try {
      await map!.clearCircles();
      await map!.clearSymbols();
      for (final member in widget.controller.members) {
        if (!mounted) break;
        final fix = widget.controller.locations[member.id];
        if (fix == null) continue;
        await map!.addCircle(
          CircleOptions(
            geometry: LatLng(fix.latitude, fix.longitude),
            circleRadius: 9,
            circleColor: fix.isStale(DateTime.now()) ? '#8C9691' : '#16745B',
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 3,
          ),
        );
        await map!.addSymbol(
          SymbolOptions(
            geometry: LatLng(fix.latitude, fix.longitude),
            textField: member.name,
            textSize: 13,
            textOffset: const Offset(0, 1.6),
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textColor: '#173C30',
          ),
        );
      }
    } catch (_) {
      /* Provider failures leave the member list usable. */
    } finally {
      drawing = false;
      if (drawAgain && mounted) {
        drawAgain = false;
        unawaited(draw());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.controller;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MapLibreMap(
                styleString: mapStyle,
                initialCameraPosition: const CameraPosition(
                  target: LatLng(20.5937, 78.9629),
                  zoom: 3.5,
                ),
                onMapCreated: (controller) => map = controller,
                onStyleLoadedCallback: () {
                  styleReady = true;
                  unawaited(draw());
                },
                myLocationEnabled: false,
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          family.control.sharing
                              ? Icons.location_on
                              : Icons.location_off,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            family.control.sharing
                                ? family.isPrivateConnection
                                      ? 'Your location is shared only with the owner'
                                      : 'Your location is shared with family'
                                : 'Your location sharing is paused',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.9),
                  padding: const EdgeInsets.all(4),
                  child: const Text(
                    '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
                    style: TextStyle(fontSize: 9),
                  ),
                ),
              ),
              if (!styleReady)
                const Positioned(
                  bottom: 32,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Loading map… Locations are also listed below.',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 205,
          child: family.members.isEmpty
              ? const Center(
                  child: Text('Your family will appear here once connected.'),
                )
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '${family.isPrivateConnection ? 'Your connection' : 'Your family'} · ${family.members.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ...family.members.map(
                      (member) => SharedMemberTile(
                        member: member,
                        location: family.locations[member.id],
                        onTap: () {
                          final fix = family.locations[member.id];
                          if (fix != null && styleReady) {
                            map?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                LatLng(fix.latitude, fix.longitude),
                                15,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class SharedMemberTile extends StatelessWidget {
  const SharedMemberTile({
    super.key,
    required this.member,
    this.location,
    this.onTap,
    this.now,
  });
  final Member member;
  final SharedLocation? location;
  final VoidCallback? onTap;
  final DateTime? now;
  @override
  Widget build(BuildContext context) {
    final fix = location;
    final clock = now ?? DateTime.now();
    final stale = fix?.isStale(clock) ?? true;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: stale
            ? const Color(0xffe2e6e2)
            : const Color(0xffd5eddf),
        child: Text(
          member.name.isEmpty ? '?' : member.name.substring(0, 1).toUpperCase(),
        ),
      ),
      title: Text(member.name),
      subtitle: Text(
        fix == null
            ? 'No shared location'
            : '${fix.ageLabel(clock)}${stale ? ' · Stale' : ''}${fix.accuracy == null ? '' : ' · ±${fix.accuracy!.round()} m'}',
      ),
      trailing: Icon(
        stale ? Icons.schedule : Icons.location_on_outlined,
        size: 20,
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final value = await widget.controller.bridge.status();
      if (mounted) setState(() => status = value);
    } catch (_) {
      /* Permissions remain accessible through settings. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 36),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.self!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        family.isOwner
                            ? 'Family owner'
                            : 'Profile saved on this phone',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (family.isPrivateConnection) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Private connection: only the owner can see your profile and shared location. You can see only the owner and your own pin. You choose when to share.',
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SwitchListTile(
          title: const Text('Share my location'),
          subtitle: const Text('Pausing removes your shared pin.'),
          value: family.control.sharing,
          onChanged: busy
              ? null
              : (enabled) async {
                  setState(() => busy = true);
                  await perform(context, () async {
                    if (enabled && !family.control.override) {
                      await family.bridge.foregroundPermission();
                      final permission = await family.bridge.status();
                      if (permission['foreground'] != true) {
                        throw StateError(
                          'Allow location permission before sharing.',
                        );
                      }
                    }
                    await family.setSharing(enabled);
                  });
                  await refresh();
                  if (mounted) setState(() => busy = false);
                },
        ),
        const SizedBox(height: 20),
        Text('Location access', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        PermissionRow(
          label: 'While using the app',
          enabled: status['foreground'] == true,
        ),
        PermissionRow(
          label: 'Precise location',
          enabled: status['precise'] == true,
        ),
        PermissionRow(
          label: 'Background / Always access',
          enabled: status['background'] == true,
        ),
        PermissionRow(
          label: 'Location services enabled',
          enabled: status['gpsEnabled'] == true,
        ),
        const SizedBox(height: 12),
        const Text(
          'Allow location while using the app first. Then choose Always or Allow all the time for sharing with the screen locked. Keep precise location enabled for better accuracy.',
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                await perform(context, family.bridge.foregroundPermission);
                await refresh();
              },
              child: const Text('Allow location'),
            ),
            TextButton(
              onPressed: () async {
                await perform(context, family.bridge.backgroundPermission);
                await refresh();
              },
              child: const Text('Background access'),
            ),
            TextButton(
              onPressed: () => perform(context, family.bridge.openSettings),
              child: const Text('Phone settings'),
            ),
          ],
        ),
        if (status['powerSave'] == true)
          const Text(
            'Low-power mode is on. Location updates may arrive less often.',
          ),
        if (status['batteryOptimized'] == true)
          const Text(
            'Android battery restrictions may delay updates. You can review this app’s battery settings if sharing stops.',
          ),
        if ((status['lastError'] as String? ?? '').isNotEmpty)
          Text(
            status['lastError'] as String,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton(
          onPressed: busy
              ? null
              : () => perform(context, () async {
                  if (family.control.sharing && !family.control.override) {
                    await family.bridge.start(family.self!.id);
                  }
                  await refresh();
                }, success: 'Tracking status refreshed.'),
          child: const Text('Resume tracking'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Battery-conscious tracking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Updates aim for about a minute while moving and slow down when stationary. Your phone controls background availability. The map shows the time and accuracy of the latest fix.',
        ),
        if (family.isOwner) ...[
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Family administration'),
            subtitle: const Text('Approve phones and recover profiles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AdminPage(controller: family),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('My shared location'),
            subtitle: Text(
              family.control.override
                  ? 'Manual pin active · owner controls'
                  : 'Use GPS or choose a pin',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ManualLocationPage(controller: family),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow({super.key, required this.label, required this.enabled});
  final String label;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          enabled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 20,
          color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(
          enabled ? 'Allowed' : 'Check settings',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final requests = widget.controller.pairingRequests();
  late final members = widget.controller.familyMembers();
  bool busy = false;
  Future<void> approve(PairingRequest request, List<Member> profiles) async {
    String code = '';
    String selected = 'new';
    bool ownerOnly = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Approve ${request.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ask this person for the code displayed on their phone. For recovery, select their existing profile; the old phone loses access.',
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => code = value,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Pairing code from their phone',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: 'new',
                      child: Text('Create a new profile'),
                    ),
                    ...profiles
                        .where(
                          (member) =>
                              member.id != widget.controller.ownerMemberId,
                        )
                        .map(
                          (member) => DropdownMenuItem(
                            value: member.id,
                            child: Text('Recover ${member.name}'),
                          ),
                        ),
                  ],
                  onChanged: (value) => setDialogState(() => selected = value!),
                  decoration: const InputDecoration(labelText: 'Profile'),
                ),
                if (selected == 'new')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Private connection (only you)'),
                    subtitle: const Text(
                      'Only you can see this person. They can see only you. Other family members cannot see their profile or location.',
                    ),
                    value: ownerOnly,
                    onChanged: (value) =>
                        setDialogState(() => ownerOnly = value),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Recovery keeps the existing profile’s visibility.',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (code.trim().toUpperCase() == request.code) {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'The code does not match. Check it with the family member.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    await perform(
      context,
      () => widget.controller.approve(
        request,
        recoverMemberId: selected == 'new' ? null : selected,
        ownerOnly: ownerOnly,
      ),
      success: 'Phone approved. Sharing starts when the member enables it.',
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Family administration')),
    body: StreamBuilder<List<Member>>(
      stream: members,
      builder: (context, memberSnapshot) => StreamBuilder<List<PairingRequest>>(
        stream: requests,
        builder: (context, requestSnapshot) {
          if (memberSnapshot.hasError || requestSnapshot.hasError) {
            return const Center(
              child: Text(
                'Family administration is unavailable. Check your connection.',
              ),
            );
          }
          final profiles = memberSnapshot.data ?? [];
          final waiting = requestSnapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Waiting for approval',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (waiting.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No pending phones.'),
                ),
              ...waiting.map(
                (request) => Card(
                  child: ListTile(
                    title: Text(request.name),
                    subtitle: const Text(
                      'Verify the pairing code with this person',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Reject request',
                          onPressed: busy
                              ? null
                              : () => perform(
                                  context,
                                  () => widget.controller.reject(request),
                                ),
                          icon: const Icon(Icons.close),
                        ),
                        IconButton(
                          tooltip: 'Approve or recover profile',
                          onPressed: busy
                              ? null
                              : () => approve(request, profiles),
                          icon: const Icon(Icons.check),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Family profiles',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ...profiles.map(
                (member) => ListTile(
                  title: Text(member.name),
                  subtitle: Text(
                    member.id == widget.controller.ownerMemberId
                        ? 'Owner · recover using email sign-in'
                        : member.ownerOnly
                        ? 'Private connection · visible only to you'
                        : 'One approved phone · family sharing',
                  ),
                  trailing: member.id == widget.controller.ownerMemberId
                      ? null
                      : IconButton(
                          tooltip: 'Remove member',
                          onPressed: busy
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Remove ${member.name}?'),
                                      content: const Text(
                                        'Their phone will lose family access and their shared location will be removed.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    await perform(
                                      context,
                                      () => widget.controller.removeMember(
                                        member,
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class ManualLocationPage extends StatefulWidget {
  const ManualLocationPage({super.key, required this.controller});
  final FamilyController controller;
  @override
  State<ManualLocationPage> createState() => _ManualLocationPageState();
}

class _ManualLocationPageState extends State<ManualLocationPage> {
  LatLng? selected;
  MapLibreMapController? map;
  bool ready = false;
  bool busy = false;
  Future<void> choose(LatLng point) async {
    setState(() => selected = point);
    if (ready) {
      await map?.clearCircles();
      await map?.addCircle(
        CircleOptions(
          geometry: point,
          circleRadius: 10,
          circleColor: '#16745B',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My shared location')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            widget.controller.control.override
                ? 'Your chosen pin stays active until you restore GPS. Tap the map to move it.'
                : 'Tap the map to choose the location your family sees. This replaces your GPS pin and pauses your GPS tracking.',
          ),
        ),
        Expanded(
          child: MapLibreMap(
            styleString: mapStyle,
            initialCameraPosition: const CameraPosition(
              target: LatLng(20.5937, 78.9629),
              zoom: 4,
            ),
            onMapCreated: (controller) => map = controller,
            onStyleLoadedCallback: () => ready = true,
            onMapClick: (_, point) {
              if (!busy) unawaited(choose(point));
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(4),
          child: Text(
            '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors',
            style: TextStyle(fontSize: 9),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${selected!.latitude.toStringAsFixed(5)}, ${selected!.longitude.toStringAsFixed(5)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                FilledButton(
                  onPressed: selected == null || busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await perform(
                            context,
                            () => widget.controller.setManual(
                              selected!.latitude,
                              selected!.longitude,
                            ),
                            success: 'Your chosen location is now shared.',
                          );
                          if (mounted) setState(() => busy = false);
                        },
                  child: Text(busy ? 'Saving…' : 'Share this pin'),
                ),
                if (widget.controller.control.override)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            await perform(
                              context,
                              widget.controller.clearManual,
                              success: 'GPS sharing restored.',
                            );
                            if (mounted) setState(() => busy = false);
                          },
                    child: const Text('Restore GPS sharing'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
