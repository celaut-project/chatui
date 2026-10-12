import 'package:flutter/material.dart';

import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../services/address_label_service.dart';
import '../../services/contacts_service.dart';
import '../../theme/argus_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/soft_card.dart';
import 'settings_shared.dart';

/// Contacts (people you pay) and labels (names for your own addresses).
class AddressBookPage extends StatelessWidget {
  const AddressBookPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([addressLabelService, contactsService]),
      builder: (context, _) {
        final colors = ArgusColors.of(context);
        final labels = addressLabelService.labels;
        final t = context.l10n;
        return SettingsPage(
          title: t.addressBookTitle,
          children: [
            SettingsGroup(
              title: t.commonContacts,
              scope: t.settingsScopeAppWide,
              children: [
                SettingsRow(
                  icon: Icons.people_outline,
                  title: t.commonContacts,
                  subtitle: contactsService.contacts.isEmpty
                      ? t.addressBookContactsEmpty
                      : t.addressBookContactsSaved(contactsService.contacts.length),
                  onTap: () => Navigator.pushNamed(context, '/contacts'),
                ),
              ],
            ),
            SectionLabel(t.addressBookLabelsSection, scope: t.settingsScopeAppWide),
            const SizedBox(height: 10),
            if (labels.isEmpty)
              SoftCard(
                child: EmptyState(
                  compact: true,
                  icon: Icons.label_outline,
                  title: t.addressBookNoLabelsTitle,
                  body: t.addressBookNoLabelsBody,
                ),
              )
            else
              SoftCard(
                padding: EdgeInsets.zero,
                child: DividedColumn(
                  indent: 16,
                  children: [
                    for (final e in labels.entries)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(shorten(e.key, head: 12, tail: 10),
                                      style: monoStyle(context, size: 11.5).copyWith(color: colors.muted)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: t.addressBookRemoveLabel,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => addressLabelService.removeLabel(e.key),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
