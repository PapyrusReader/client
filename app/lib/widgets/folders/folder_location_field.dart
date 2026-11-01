import 'package:flutter/material.dart';
import 'package:papyrus/folders/directory_access.dart';

class FolderLocationField extends StatelessWidget {
  const FolderLocationField({super.key, required this.grant});

  final FolderGrant grant;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: grant.location == grant.name ? 'Selected folder' : 'Folder path',
      prefixIcon: const Icon(Icons.folder_outlined),
    ),
    child: SelectableText(grant.location, style: Theme.of(context).textTheme.bodyLarge),
  );
}
