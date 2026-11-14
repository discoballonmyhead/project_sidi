import 'package:flutter/material.dart';

import '../../../core/network/rpc.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/domain/catalog.dart';
import '../../discover/domain/discover.dart';

const _currencies = {'INR': 'INR · Indian rupee', 'USD': 'USD · US dollar', 'EUR': 'EUR · Euro', 'GBP': 'GBP · Pound sterling', 'AED': 'AED · UAE dirham', 'AUD': 'AUD · Australian dollar', 'SGD': 'SGD · Singapore dollar'};

/// The application form for a new organisation.
Future<Json?> showOrgCreateForm(BuildContext context, Catalog catalog) => showFormSheet(
  context,
  title: 'Create an organisation',
  description: 'Our team reviews every application, usually within a day. You can set everything up while you wait.',
  submitLabel: 'Submit for approval',
  fields: [
    const FieldSpec.text('name', 'Name', required: true, hint: 'Smash Arena'),
    FieldSpec.multiChoice('sports', 'Sports', {for (final sport in catalog.sports) sport.code: sport.name}, required: true),
    const FieldSpec.multiline('description', 'About', hint: 'What you offer, in a sentence or two'),
    const FieldSpec.text('city', 'City'),
    const FieldSpec.text('address', 'Address'),
    const FieldSpec.text('contact_email', 'Contact e-mail'),
    const FieldSpec.text('contact_phone', 'Contact phone'),
    const FieldSpec.choice('currency', 'Currency', _currencies, initial: 'INR'),
    const FieldSpec.multiline('message', 'Note to the reviewers', hint: 'Anything that helps us approve you quickly'),
  ],
);

Future<Json?> showOrgEditForm(BuildContext context, Catalog catalog, Org org) => showFormSheet(
  context,
  title: 'Organisation details',
  fields: [
    FieldSpec.text('name', 'Name', initial: org.name, required: true),
    FieldSpec.multiChoice('sports', 'Sports', {for (final sport in catalog.sports) sport.code: sport.name}, initial: org.sports, required: true),
    FieldSpec.multiline('description', 'About', initial: org.description),
    FieldSpec.text('city', 'City', initial: org.city),
    FieldSpec.text('address', 'Address', initial: org.address),
    FieldSpec.text('contact_email', 'Contact e-mail', initial: org.contactEmail),
    FieldSpec.text('contact_phone', 'Contact phone', initial: org.contactPhone),
  ],
);
