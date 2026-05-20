import 'package:flutter/material.dart';

class AdaptiveTextField extends StatefulWidget {
  final String? labelText;
  final String? hintText;
  final int maxLines;
  final TextEditingController? controller;
  final void Function(String)? onChanged;

  const AdaptiveTextField({
    super.key,
    this.labelText,
    this.hintText,
    this.maxLines = 5,
    this.controller,
    this.onChanged,
  });

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  late FocusNode _focusNode;
  int _currentMaxLines = 1;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {
        _currentMaxLines = _focusNode.hasFocus ? widget.maxLines : 1;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: _currentMaxLines,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
