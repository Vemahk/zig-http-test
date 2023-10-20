htmx.onLoad(function(content){
    const times = content.querySelectorAll("time.epoch");
    for(let i=0; i<times.length; i++)
        renderEpoch(times[i]);
    
    if(content.nodeName === "TIME" && content.classList.contains("epoch"))
        renderEpoch(content);
});

function renderEpoch(time) {
    const epoch = parseInt(time.innerText) * 1000;
    const date = new Date(epoch);
    time.innerText = date.toLocaleString();
    time.setAttribute("datetime", date.toISOString());
    time.classList.remove("epoch");
}
