import maplibregl from "maplibre-gl";
const Map = {
    mounted() {
        this.props = { id: this.el.getAttribute("data-id") };
        this.handleEvent(`map:${this.props.id}:init`, ({ ml }) => {
            const map = {container: "map", style: ml}
            this.props.map = new maplibregl.Map(map);
        });
    },
};

export default Map;
