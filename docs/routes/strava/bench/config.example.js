// Copy to config.js and put your own key in it. config.js is gitignored — the
// key never reaches the repo, and nobody but you needs to see its value.
//
// Get one at console.ncloud.com -> AI·NAVER API -> Maps -> Application:
//   1. register an application, enable "Web Dynamic Map"
//   2. add http://localhost:5178 to the service URL allowlist
//   3. copy the Client ID (NOT the client secret — this page never needs it)
//
// Naver renamed the query parameter: newer keys use ncpKeyId, older ones use
// ncpClientId. Set which one yours is; the page reads this and builds the URL.
window.NAVER_MAP = {
  key: 'PUT_YOUR_CLIENT_ID_HERE',
  param: 'ncpKeyId',        // or 'ncpClientId' for an older key
};
