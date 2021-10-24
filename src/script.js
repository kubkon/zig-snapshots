var callbacks = {};

function translate(anchorElement, svgId, x, y) {
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

  Array.from(anchorElement.getElementsByTagName("rect")).forEach((el) => {
    el.classList.add("reloc");
    callbacks[svgId].push(() => {
      el.classList.remove("reloc");
    });
  });

  traverseLateral(anchorElement.parentElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    callbacks[svgId].push(() => {
      el.setAttributeNS(null, "transform", "");
    });
  });

  const parentGElement = traverseUp(anchorElement, (el) => el.tagName === "svg");

  traverseLateral(parentGElement.nextSibling, (el) => {
    el.setAttributeNS(null, "transform", `translate(${x}, ${y})`);
    callbacks[svgId].push(() => {
      el.setAttributeNS(null, "transform", "");
    });
  });
}

function drawArrows(anchorElement, svgId, x, y) {
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
    callbacks[svgId].push(() => {
      el.classList.remove("arrow");
      el.setAttributeNS(null, "marker-end", "");
    });
  });
}

function assert(condition, message) {
  if (!condition) {
    throw message || "Assertion failed";
  }
}

function onClick(el, anchorElementId, svgId, x, y) {
  if (!(svgId in callbacks)) {
    callbacks[svgId] = [];
  }

  while (true) {
    let cb = callbacks[svgId].pop();
    if (cb == null) break;
    cb();
  }

  el.previousSibling.classList.add("bold-font");
  el.classList.add("highlight");
  callbacks[svgId].push(() => {
    el.previousSibling.classList.remove("bold-font");
    el.classList.remove("highlight");
  });

  const anchorElement = document.getElementById(anchorElementId);
  anchorElement.classList.remove("hidden");
  callbacks[svgId].push(() => {
    anchorElement.classList.add("hidden");
  });

  translate(anchorElement, svgId, x, y);
  drawArrows(anchorElement, svgId, x, y);
}
