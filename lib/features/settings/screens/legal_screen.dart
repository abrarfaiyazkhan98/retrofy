import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show showLicensePage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

const _repository = 'https://github.com/abrarfaiyazkhan98/retrofy';

/// Retrofy's own licence (the repository's LICENSE file), which requires its
/// copyright notice to travel with every binary.
const _retrofyLicense = r'''
Copyright (c) 2025, Aditya R
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. All advertising materials mentioning features or use of this software
   must display the following acknowledgement:
   This product includes software developed by Aditya R.
4. Neither the name of Aditya R nor the
   names of its contributors may be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';

var _licenseRegistered = false;

void _registerRetrofyLicense() {
  if (_licenseRegistered) return;
  _licenseRegistered = true;
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks([
        'Retrofy',
        'Classipod',
      ], _retrofyLicense),
    ),
  );
}

enum LegalItem {
  licenses,
  privacyPolicy,
  terms,
  sourceCode;

  String title(BuildContext context) => switch (this) {
    licenses => context.localization.openSourceLicensesTitle,
    privacyPolicy => context.localization.privacyPolicyTitle,
    terms => context.localization.termsTitle,
    sourceCode => context.localization.sourceCodeTitle,
  };

  Uri? get uri => switch (this) {
    licenses => null,
    privacyPolicy => Uri.parse('$_repository/blob/master/privacy-policy.md'),
    terms => Uri.parse('$_repository/blob/master/terms-and-conditions.md'),
    sourceCode => Uri.parse(_repository),
  };
}

/// The licence notices the GPL and bundled packages require, plus the
/// privacy policy and terms. Replaces the former About screen.
class LegalScreen extends ConsumerStatefulWidget {
  const LegalScreen({super.key});

  @override
  ConsumerState createState() => _LegalScreenState();
}

class _LegalScreenState extends ConsumerState<LegalScreen> with CustomScreen {
  @override
  String get routeName => Routes.legal.name;

  @override
  List<LegalItem> get displayItems => LegalItem.values;

  @override
  Future<void> onSelectPressed() => _open(displayItems[selectedDisplayItem]);

  Future<void> _open(LegalItem item) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(item));
    final uri = item.uri;
    if (uri == null) {
      _registerRetrofyLicense();
      showLicensePage(
        context: context,
        applicationName: context.localization.appTitle,
        applicationLegalese: context.localization.legalese,
        useRootNavigator: true,
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: ListView.builder(
        controller: scrollController,
        itemCount: displayItems.length,
        itemBuilder: (context, index) => DisplayListTile(
          text: displayItems[index].title(context),
          isSelected: index == selectedDisplayItem,
          onTap: () => unawaited(_open(displayItems[index])),
        ),
      ),
    );
  }
}
