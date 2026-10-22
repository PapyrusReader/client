import 'package:flutter/material.dart';
import 'package:papyrus/widgets/shared/app_page_bar.dart';

class SearchOptionsPage extends StatelessWidget {
  const SearchOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppPageBar(context: context, title: const Text("Search options")),
      body: const SafeArea(child: Placeholder()), // body: ,
    );
  }
}
