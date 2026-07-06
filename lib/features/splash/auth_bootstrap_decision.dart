bool shouldSendBootstrapFailureToLogin(int statusCode) {
  return statusCode == 401 || statusCode == 403;
}
