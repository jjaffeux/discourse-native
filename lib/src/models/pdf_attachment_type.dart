bool isPdfAttachment(String filename, String url) =>
    Uri.tryParse(url)?.path.toLowerCase().endsWith('.pdf') == true ||
    // Discourse's upload short URL carries no filename or extension.
    (url.startsWith('upload://') &&
        filename.split('|').first.trim().toLowerCase().endsWith('.pdf'));
