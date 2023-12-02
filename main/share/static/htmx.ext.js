htmx.onLoad(function(content){
    const times = content.querySelectorAll("time");
    for(let i=0; i<times.length; i++)
        renderEpoch(times[i]);
    
    if(content.nodeName === "TIME")
        renderEpoch(content);
});

function renderEpoch(time) {
    const epochAttr = time.getAttribute("epoch");
    if(epochAttr == null) return;
    const epoch = parseInt(epochAttr) * 1000;
    const date = new Date(epoch);
    time.innerText = date.toLocaleString();
    time.setAttribute("datetime", date.toISOString());
}
