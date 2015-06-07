/*
 * small.form.js
 * Fonctions pour améliorer la saisie d'un formulaire
 *
 * Fonctionalités :
 * - Active le bouton de validation dès que les données du formulaire sont modifiées
 * - Demande confirmation avant de quitter un formulaire avec des données non enregistrées
 * - Enregistre (valide) le formulaire quand l'utilisateur appuie sur Ctrl+S
 *
 * Configuration :
 * - Le bouton de validation doit avoir l'id "submit"
 * - Prend en compte les balises input et textarea
 *
 */


/* Active le bouton [Modifier] dès que le contenu est modifié */
var submit = document.getElementById("submit"),
    inputs = document.querySelectorAll("input, textarea");
[].forEach.call(inputs, function (input) {
  input.addEventListener("input", function(e) { submit.disabled = false; })
});
submit.disabled = true; // Mais au début il est forcément désactivé

/* Fonction pour prévenir qu'il existe du contenu modifié */
var alerte = function (e) {
  // Si le bouton [Modifier] est désactivé (ie le contenu n'a pas été modifié)
  var submit = document.getElementById("submit");
  // Alors il n'est pas nécessaire de faire confirmer la sortie de page
  if (submit.disabled) return;
  // Défini un message pour que le navigateur affiche une fenêtre de confirmation
  var e = e || window.event,
      message = "Les informations en cours de saisie n'ont pas été enregistrées. ";
  message += "Elles seront perdues si vous quittez ou rechargez la page en cours.";
  if (e) e.returnValue = message;
  return message;
};

/* Active la confirmation de sortie de page s'il existe du contenu modifié */
window.addEventListener("beforeunload", alerte);
/* Et désactive la confirmation dès qu'on enregistre le contenu */
document.forms[0].addEventListener("submit", function(e) {
  window.removeEventListener("beforeunload", alerte);
});

/* Détourne Ctrl+S pour enregistrer la saisie en cours */
/* http://stackoverflow.com/questions/4446987/overriding-controls-save-functionality-in-browser */
document.addEventListener("keydown", function(e) {
  if (e.keyCode == 83 && (navigator.platform.match("Mac") ? e.metaKey : e.ctrlKey)) {
    // Désactive le comportement par défaut
    e.preventDefault();
    // Si le bouton [Modifier] est activé (ie le contenu a bien été modifié)
    var submit = document.getElementById("submit");
    // Alors il est possible de sauvegarder
    if (!submit.disabled) submit.click();
  }
}, false);
