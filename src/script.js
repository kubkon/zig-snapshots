var activeElements = [];
var translatedElements = [];

function translate(anchorElementId, x, y) {
  const traverseUp = function (el, cond) {
    if (cond(el.parentElement)) {
      return el;
    }
    return traverseUp(el.parentElement, cond);
  };

  const traverseLateral = function (el, action) {
    if (el == null) return;
    action(el);
    traverseLateral(el.nextSibling, action);
  };

  // Undo the state for any active element
  while (true) {
    let active = activeElements.pop();
    if (active == null) break;
    active.classList.add("hidden");
    const rects = Array.from(active.getElementsByTagName("rect"));
    rects.forEach((el) => {
      el.classList.remove("reloc");
    });
  }

  while (true) {
    let translated = translatedElements.pop();
    if (translated == null) break;
    translated.setAttributeNS(null, "transform", "");
  }

  const anchorElement = document.getElementById(anchorElementId);
  activeElements.push(anchorElement);
  anchorElement.classList.remove("hidden");
  const anchorRects = Array.from(anchorElement.getElementsByTagName("rect"));
  anchorRects.forEach((el) => {
    el.classList.add("reloc");
  });

  traverseLateral(anchorElement.parentElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    translatedElements.push(el);
  })

  const parentGElement = traverseUp(anchorElement, (el) => el.tagName === "svg");
  traverseLateral(parentGElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    translatedElements.push(el);
  });
}

function assert(condition, message) {
  if (!condition) {
    throw message || "Assertion failed";
  }
}
