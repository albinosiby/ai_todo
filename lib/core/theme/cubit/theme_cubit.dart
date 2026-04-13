import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeInitial());

  void toggleTheme() {
    if (state.themeMode == ThemeMode.light || state.themeMode == ThemeMode.system) {
       // Typically, you might want to resolve system theme first, but simple toggle assumes light -> dark -> light.
       emit(const ThemeChanged(ThemeMode.dark));
    } else {
       emit(const ThemeChanged(ThemeMode.light));
    }
  }

  void setTheme(ThemeMode mode) {
    emit(ThemeChanged(mode));
  }
}
