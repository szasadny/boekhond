shh Boekhond progressive enhancement, gecompileerd uit Dogescript naar static/js/boekhond.js.
shh Baseline werkt volledig zonder JS: alles hieronder is feature-detected en additief.
shh De DOM-logica staat als plain JS (Dogescript laat onbekende regels door); Dogescript's
shh eigen keyword-syntax mis-compileert echte DOM-code, dus we volgen de "gaps -> plain JS"-regel.
(function () {
  'use strict';

  shh Spiegelt app/services/bijlagen.doge: TOEGESTANE_EXT + MAX_BYTES. Alleen UX,
  shh nooit de security-grens: bijlagen.bewaar hervalideert altijd server-side.
  var TOEGESTANE_EXT = ['pdf', 'png', 'jpg', 'jpeg'];
  var MAX_BYTES = 10485760;

  shh --- Memoriaalform: "+ regel"-knop (kloont een lege regel; server accepteert N regels) ---
  function verrijkMemoriaal() {
    var form = document.querySelector('form[action$="/journaal/memoriaal"]');
    if (!form) { return; }
    var tbody = form.querySelector('tbody');
    if (!tbody) { return; }

    var knop = document.createElement('button');
    knop.type = 'button';
    knop.textContent = '+ regel';
    knop.className = 'regel-toevoegen';
    knop.addEventListener('click', function () {
      var rijen = tbody.querySelectorAll('tr');
      if (rijen.length === 0) { return; }
      var kopie = rijen[rijen.length - 1].cloneNode(true);
      kopie.querySelectorAll('input, select').forEach(function (el) {
        if (el.tagName === 'SELECT') { el.selectedIndex = 0; } else { el.value = ''; }
      });
      tbody.appendChild(kopie);
    });
    form.insertBefore(knop, form.lastElementChild);
  }

  shh --- Uploadform: bestandsnaam tonen, client-side check, drag-and-drop ---
  function extVan(naam) {
    var punt = naam.lastIndexOf('.');
    if (punt < 0) { return ''; }
    return naam.slice(punt + 1).toLowerCase();
  }

  function bestandFout(bestand) {
    if (TOEGESTANE_EXT.indexOf(extVan(bestand.name)) < 0) {
      return 'Alleen pdf, png of jpg toegestaan.';
    }
    if (bestand.size > MAX_BYTES) {
      return 'Bestand is te groot (max 10 MB).';
    }
    return '';
  }

  function verrijkUpload() {
    var input = document.querySelector('input[type="file"][name="bestand"]');
    if (!input) { return; }
    var form = input.form;

    var status = document.createElement('p');
    status.className = 'upload-status';
    status.setAttribute('aria-live', 'polite');
    input.parentNode.insertAdjacentElement('afterend', status);

    function toon() {
      if (input.files.length === 0) { status.textContent = ''; status.classList.remove('fout'); return; }
      var fout = bestandFout(input.files[0]);
      status.textContent = fout ? fout : ('Gekozen: ' + input.files[0].name);
      status.classList.toggle('fout', !!fout);
    }

    input.addEventListener('change', toon);

    if (form) {
      form.addEventListener('submit', function (e) {
        if (input.files.length === 0) { return; }
        if (bestandFout(input.files[0])) {
          e.preventDefault();
          toon();
        }
      });
    }

    shh Drag-and-drop: het label is de drop-zone; gedropte files gaan in de input.
    var zone = input.closest('label') || input.parentNode;
    zone.classList.add('dropzone');
    ['dragenter', 'dragover'].forEach(function (naam) {
      zone.addEventListener(naam, function (e) { e.preventDefault(); zone.classList.add('sleep'); });
    });
    ['dragleave', 'drop'].forEach(function (naam) {
      zone.addEventListener(naam, function (e) { e.preventDefault(); zone.classList.remove('sleep'); });
    });
    zone.addEventListener('drop', function (e) {
      if (!e.dataTransfer || e.dataTransfer.files.length === 0) { return; }
      input.files = e.dataTransfer.files;
      toon();
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    verrijkMemoriaal();
    verrijkUpload();
  });
})();
