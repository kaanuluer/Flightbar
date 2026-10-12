(function () {
  var readURL = "https://abacus.jasoncameron.dev/get/com.uluersolutions.flightbar/downloads";
  var hitURL = "https://abacus.jasoncameron.dev/hit/com.uluersolutions.flightbar/downloads";

  function label(value) {
    var formatted = new Intl.NumberFormat("en").format(value);
    return formatted + (value === 1 ? " download" : " downloads");
  }

  function show(value) {
    if (!Number.isFinite(value)) return;
    document.querySelectorAll("[data-download-count]").forEach(function (node) {
      node.textContent = label(value);
      node.hidden = false;
    });
  }

  fetch(readURL)
    .then(function (response) { return response.json(); })
    .then(function (data) { show(Number(data.value)); })
    .catch(function () {});

  document.querySelectorAll("[data-download]").forEach(function (link) {
    link.addEventListener("click", function () {
      fetch(hitURL, { keepalive: true })
        .then(function (response) { return response.json(); })
        .then(function (data) { show(Number(data.value)); })
        .catch(function () {});
    });
  });
})();
