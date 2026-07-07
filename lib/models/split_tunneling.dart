enum SplitTunnelingMode {
  off,
  onlySelected,
  exceptSelected,
}

extension SplitTunnelingModeExt on SplitTunnelingMode {
  String get key {
    switch (this) {
      case SplitTunnelingMode.off:
        return 'off';
      case SplitTunnelingMode.onlySelected:
        return 'only_selected';
      case SplitTunnelingMode.exceptSelected:
        return 'except_selected';
    }
  }

  String get title {
    switch (this) {
      case SplitTunnelingMode.off:
        return 'Выключено';
      case SplitTunnelingMode.onlySelected:
        return 'Только эти приложения';
      case SplitTunnelingMode.exceptSelected:
        return 'Кроме этих приложений';
    }
  }

  String get description {
    switch (this) {
      case SplitTunnelingMode.off:
        return 'Весь трафик приложений обрабатывается одинаково';
      case SplitTunnelingMode.onlySelected:
        return 'Через туннель пойдут только выбранные приложения';
      case SplitTunnelingMode.exceptSelected:
        return 'Через туннель пойдут все приложения, кроме выбранных';
    }
  }

  static SplitTunnelingMode fromKey(String key) {
    switch (key) {
      case 'only_selected':
        return SplitTunnelingMode.onlySelected;
      case 'except_selected':
        return SplitTunnelingMode.exceptSelected;
      default:
        return SplitTunnelingMode.off;
    }
  }
}
