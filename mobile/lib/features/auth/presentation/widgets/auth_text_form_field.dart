import 'package:flutter/material.dart';

class AuthTextFormField extends StatelessWidget {
  const AuthTextFormField({
    super.key,
    required this.config,
    this.enabled = true,
    this.obscureText,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  final AuthTextFormFieldConfig config;
  final bool enabled;
  final bool? obscureText;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            config.label,
            style: text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextFormField(
          key: config.fieldKey,
          controller: config.controller,
          enabled: enabled,
          keyboardType: config.keyboardType,
          autofillHints: config.autofillHints,
          textInputAction: config.textInputAction,
          autocorrect: config.autocorrect,
          obscureText: obscureText ?? config.obscureText,
          autovalidateMode: config.autovalidateMode,
          decoration: InputDecoration(
            hintText: config.hintText,
            suffixIcon: suffixIcon,
          ),
          validator: validator ?? config.validator,
          onFieldSubmitted: onFieldSubmitted,
        ),
      ],
    );
  }
}

class AuthTextFormFieldConfig {
  const AuthTextFormFieldConfig({
    required this.label,
    required this.fieldKey,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.autocorrect = true,
    this.obscureText = false,
    this.autovalidateMode,
    this.validator,
  });

  final String label;
  final Key fieldKey;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool obscureText;
  final AutovalidateMode? autovalidateMode;
  final FormFieldValidator<String>? validator;
}
