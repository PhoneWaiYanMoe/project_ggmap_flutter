import 'package:flutter/material.dart';
import '../services/language_service.dart';

class LanguageSelector extends StatelessWidget {
  final LanguageService languageService;
  final bool isCompact;

  const LanguageSelector({
    super.key,
    required this.languageService,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageService,
      builder: (context, child) {
        if (isCompact) {
          return _buildCompactSelector(context);
        }
        return _buildFullSelector(context);
      },
    );
  }

  Widget _buildCompactSelector(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showLanguageDialog(context),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  languageService.currentLanguage.flag,
                  style: TextStyle(fontSize: 20),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 20, color: Colors.grey[700]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullSelector(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Text(
          languageService.currentLanguage.flag,
          style: TextStyle(fontSize: 24),
        ),
        title: Text(
          languageService.translate('language'),
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(languageService.currentLanguage.name),
        trailing: Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _showLanguageDialog(context),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.language, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    languageService.translate('change_language'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...AppLanguage.values.map((language) => _buildLanguageOption(
              context,
              language,
              language == languageService.currentLanguage,
            )),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(BuildContext context, AppLanguage language, bool isSelected) {
    return ListTile(
      leading: Text(language.flag, style: TextStyle(fontSize: 28)),
      title: Text(
        language.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
          : null,
      onTap: () {
        languageService.setLanguage(language);
        Navigator.pop(context);
      },
    );
  }
}

// Compact floating language button
class FloatingLanguageButton extends StatelessWidget {
  final LanguageService languageService;

  const FloatingLanguageButton({
    super.key,
    required this.languageService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageService,
      builder: (context, child) {
        return FloatingActionButton(
          mini: true,
          backgroundColor: Colors.white,
          elevation: 4,
          onPressed: () => _showLanguageBottomSheet(context),
          child: Text(
            languageService.currentLanguage.flag,
            style: TextStyle(fontSize: 20),
          ),
        );
      },
    );
  }

  void _showLanguageBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                languageService.translate('change_language'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...AppLanguage.values.map((language) => ListTile(
              leading: Text(language.flag, style: TextStyle(fontSize: 32)),
              title: Text(
                language.name,
                style: TextStyle(fontSize: 16),
              ),
              trailing: language == languageService.currentLanguage
                  ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                languageService.setLanguage(language);
                Navigator.pop(context);
              },
            )),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}