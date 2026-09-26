extends Node
## Provider boundary for account authentication. Concrete providers emit a
## Supabase session; account/profile code never depends on a specific login UI.

signal session_received(session: Dictionary)
signal action_finished(action: String, success: bool, message: String)
signal signed_out

func sign_up(_email: String, _password: String) -> void:
	push_error("AuthProvider.sign_up must be implemented by a provider.")

func sign_in(_email: String, _password: String) -> void:
	push_error("AuthProvider.sign_in must be implemented by a provider.")

func sign_out(_access_token: String) -> void:
	push_error("AuthProvider.sign_out must be implemented by a provider.")

func refresh_session(_refresh_token: String) -> void:
	push_error("AuthProvider.refresh_session must be implemented by a provider.")

func request_password_reset(_email: String, _redirect_url: String) -> void:
	push_error("AuthProvider.request_password_reset must be implemented by a provider.")
