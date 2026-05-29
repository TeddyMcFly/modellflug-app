const adminAccountEmails = {
  'teddroste@me.com',
  'linus@web.de',
};

bool isAdminEmail(String? email) {
  return adminAccountEmails.contains(email?.trim().toLowerCase());
}
