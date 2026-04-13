import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _authRepository;

  AuthCubit({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    _authRepository.user.listen((User? firebaseUser) async {
      if (firebaseUser != null) {
        final userModel = await _authRepository.getUserData(firebaseUser.uid);
        if (userModel != null) {
          emit(Authenticated(userModel));
        } else {
          emit(Unauthenticated());
        }
      } else {
        emit(Unauthenticated());
      }
    });
  }

  Future<void> signIn(String email, String password) async {
    try {
      emit(AuthLoading());
      final user = await _authRepository.signInWithEmail(email, password);
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(const AuthError("Failed to sign in. User data not found."));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> signUp(String email, String password, String displayName) async {
    try {
      emit(AuthLoading());
      final user = await _authRepository.signUpWithEmail(email, password, displayName);
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(const AuthError("Failed to sign up. User data not found."));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    emit(Unauthenticated());
  }
}
