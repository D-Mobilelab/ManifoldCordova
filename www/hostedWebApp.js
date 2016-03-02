var hostedwebapp = {
  loadManifest: function (successCallback, errorCallback, manifestFileName) {
    cordova.exec(successCallback, errorCallback, "HostedWebApp", "loadManifest", [manifestFileName]);
  },
  getManifest: function (successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, "HostedWebApp", "getManifest", []);
  }
}

module.exports = hostedwebapp;
