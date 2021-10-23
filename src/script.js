var activeElements = [];
var translatedElements = [];

function reset() {
  while (true) {
    let active = activeElements.pop();
    if (active == null) break;
    active.classList.add("hidden");
    Array.from(active.getElementsByTagName("rect")).forEach((el) => {
      el.classList.remove("reloc");
    });
    Array.from(active.getElementsByTagName("path")).forEach((el) => {
      el.classList.remove("arrow");
      el.setAttributeNS(null, "marker-end", "");
    });
  }

  while (true) {
    let translated = translatedElements.pop();
    if (translated == null) break;
    translated.setAttributeNS(null, "transform", "");
  }
}

function translate(anchorElementId, svgId, x, y) {
  const traverseUp = function (el, cond) {
    if (cond(el.parentElement)) { return el;
    }
    return traverseUp(el.parentElement, cond);
  };

  const traverseLateral = function (el, action, directionDown = true) {
    if (el == null) return;
    action(el);
    traverseLateral(directionDown ? el.nextSibling : el.previousSibling, action, directionDown);
  };

  const anchorElement = document.getElementById(anchorElementId);
  activeElements.push(anchorElement);
  anchorElement.classList.remove("hidden");
  Array.from(anchorElement.getElementsByTagName("rect")).forEach((el) => {
    el.classList.add("reloc");
  });

  traverseLateral(anchorElement.parentElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    translatedElements.push(el);
  });

  const parentGElement = traverseUp(anchorElement, (el) => el.tagName === "svg");

  traverseLateral(parentGElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    translatedElements.push(el);
  });
}

function drawArrows(anchorElementId, svgId, x, y) {
  const anchorElement = document.getElementById(anchorElementId);
  const baseY = parseFloat(anchorElement.getElementsByTagName("rect")[0].getAttributeNS(null, "y"));
  Array.from(anchorElement.getElementsByTagName("path")).forEach((el) => {
    const x1 = parseFloat(el.getAttributeNS(null, "x1"));
    const y1 = parseFloat(el.getAttributeNS(null, "y1"));
    const x2 = parseFloat(el.getAttributeNS(null, "x2"));
    let y2 = parseFloat(el.getAttributeNS(null, "y2"));
    if (y2 > baseY) {
      y2 += y - 3;
    } else {
      y2 += 3;
    }
    const cx = x1 * 1.25;
    let cy = Math.abs(y2 - y1) / 2;
    if (y2 > baseY) {
      cy += y1;
    } else {
      cy += y2;
    }
    el.setAttributeNS(null, "d", `M ${x1} ${y1} Q ${cx} ${cy} ${x2 + 3} ${y2}`);
    el.setAttributeNS(null, "marker-end", "url(#arrowhead)");
    el.classList.add("arrow");
  });
}

function assert(condition, message) {
  if (!condition) {
    throw message || "Assertion failed";
  }
}

function resetAndTranslate(anchorElementId, svgId, x, y) {
  reset();
  translate(anchorElementId, svgId, x, y);
  drawArrows(anchorElementId, svgId, x, y);
}
