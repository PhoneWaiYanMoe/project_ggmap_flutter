// lib/src/features/auth/login_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../map/map_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

Future<void> _login() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    print('Attempting login to http://192.168.94.23:8080/signin');
    final response = await http.post(
      Uri.parse('http://192.168.94.23:8080/signin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': _usernameController.text,
        'password': _passwordController.text,
      }),
    ).timeout(Duration(seconds: 10));

    print('Login response: ${response.statusCode} - ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'] as String?;
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        print('Token saved after login: $token');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MapScreen()),
        );
      } else {
        setState(() {
          _errorMessage = 'Login succeeded, but no token received';
        });
      }
    } else {
      setState(() {
        _errorMessage = jsonDecode(response.body)['error'] ?? 'Login failed';
      });
    }
  } catch (e) {
    print('Login error: $e');
    setState(() {
      _errorMessage = 'Error: $e';
    });
  } finally {
    setState(() => _isLoading = false);
  }
}
Future<void> _signup() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    print('Attempting signup to http://192.168.94.23:8080/signup');
    final response = await http.post(
      Uri.parse('http://192.168.94.23:8080/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': _usernameController.text,
        'password': _passwordController.text,
        'email': 'user@example.com',
      }),
    ).timeout(Duration(seconds: 10));

    print('Signup response: ${response.statusCode} - ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'] as String?;
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        print('Token saved: $token');
        // Instead of navigating to MapScreen, show a success message and clear fields
        setState(() {
          _errorMessage = 'Signup successful! Please log in.';
          _usernameController.clear();
          _passwordController.clear();
        });
      } else {
        setState(() {
          _errorMessage = 'Signup succeeded, but no token received';
        });
      }
    } else {
      setState(() {
        _errorMessage = jsonDecode(response.body)['error'] ?? 'Signup failed';
      });
    }
  } catch (e) {
    print('Signup error: $e');
    setState(() {
      _errorMessage = 'Error: $e';
    });
  } finally {
    setState(() => _isLoading = false);
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            if (_errorMessage != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(_errorMessage!, style: TextStyle(color: Colors.red)),
              ),
            SizedBox(height: 16),
            _isLoading
                ? CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: _login,
                        child: Text('Login'),
                      ),
                      TextButton(
                        onPressed: _signup,
                        child: Text('Sign Up'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}