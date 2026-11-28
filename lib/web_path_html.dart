import 'dart:html' as html;

String? currentWebPath() => html.window.location.pathname;
void setWebPath(String path) => html.window.history.pushState(null, '', path);
